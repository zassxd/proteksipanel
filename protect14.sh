#!/bin/bash

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerTransferController.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "🚀 Install Proteksi Anti Modifikasi Server 3..."

# Pastikan folder tujuan ada
mkdir -p "$(dirname "$REMOTE_PATH")"
chmod 755 "$(dirname "$REMOTE_PATH")"

# Tulis ulang file baru
cat > "$REMOTE_PATH" <<'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\ServerTransfer;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Eloquent\NodeRepository;
use Pterodactyl\Repositories\Wings\DaemonTransferRepository;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;

class ServerTransferController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private AllocationRepositoryInterface $allocationRepository,
        private ConnectionInterface $connection,
        private DaemonTransferRepository $daemonTransferRepository,
        private NodeJWTService $nodeJWTService,
        private NodeRepository $nodeRepository
    ) {
    }

    /**
     * 🚫 Hanya user ID 1 yang boleh melakukan transfer server.
     */
    private function authorizeTransfer(): void
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, 'Anda tidak memiliki izin untuk mentransfer server.');
        }
    }

    /**
     * Mulai proses transfer server ke node baru.
     *
     * @throws \Throwable
     */
    public function transfer(Request $request, Server $server): RedirectResponse
    {
        // 🔒 Cegah user selain ID 1
        $this->authorizeTransfer();

        $validatedData = $request->validate([
            'node_id' => 'required|exists:nodes,id',
            'allocation_id' => 'required|bail|unique:servers|exists:allocations,id',
            'allocation_additional' => 'nullable',
        ]);

        $node_id = $validatedData['node_id'];
        $allocation_id = intval($validatedData['allocation_id']);
        $additional_allocations = array_map('intval', $validatedData['allocation_additional'] ?? []);

        $node = $this->nodeRepository->getNodeWithResourceUsage($node_id);
        if (!$node->isViable($server->memory, $server->disk)) {
            $this->alert->danger(trans('admin/server.alerts.transfer_not_viable'))->flash();
            return redirect()->route('admin.servers.view.manage', $server->id);
        }

        $server->validateTransferState();

        $this->connection->transaction(function () use ($server, $node_id, $allocation_id, $additional_allocations) {
            $transfer = new ServerTransfer();

            $transfer->server_id = $server->id;
            $transfer->old_node = $server->node_id;
            $transfer->new_node = $node_id;
            $transfer->old_allocation = $server->allocation_id;
            $transfer->new_allocation = $allocation_id;
            $transfer->old_additional_allocations = $server->allocations->where('id', '!=', $server->allocation_id)->pluck('id');
            $transfer->new_additional_allocations = $additional_allocations;
            $transfer->save();

            $this->assignAllocationsToServer($server, $node_id, $allocation_id, $additional_allocations);

            $token = $this->nodeJWTService
                ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
                ->setSubject($server->uuid)
                ->handle($transfer->newNode, $server->uuid, 'sha256');

            $this->daemonTransferRepository->setServer($server)->notify($transfer->newNode, $token);

            return $transfer;
        });

        $this->alert->success(trans('admin/server.alerts.transfer_started'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Menandai allocation sebagai milik server selama transfer berlangsung.
     */
    private function assignAllocationsToServer(Server $server, int $node_id, int $allocation_id, array $additional_allocations)
    {
        $allocations = $additional_allocations;
        $allocations[] = $allocation_id;

        $unassigned = $this->allocationRepository->getUnassignedAllocationIds($node_id);

        $updateIds = [];
        foreach ($allocations as $allocation) {
            if (!in_array($allocation, $unassigned)) {
                continue;
            }

            $updateIds[] = $allocation;
        }

        if (!empty($updateIds)) {
            $this->allocationRepository->updateWhereIn('id', $updateIds, ['server_id' => $server->id]);
        }
    }
}

EOF

# Atur permission file
chmod 644 "$REMOTE_PATH"
echo "✅ Install Proteksi Anti Modifikasi Server 3 berhasil dipasang!"
echo "📂 Lokasi file: $REMOTE_PATH"
