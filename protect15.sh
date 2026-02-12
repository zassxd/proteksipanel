#!/bin/bash

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerViewController.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "🚀 Install Proteksi Anti Modifikasi Server 4..."

# Pastikan folder tujuan ada
mkdir -p "$(dirname "$REMOTE_PATH")"
chmod 755 "$(dirname "$REMOTE_PATH")"

# Tulis ulang file baru
cat > "$REMOTE_PATH" <<'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Server;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Servers\EnvironmentService;
use Illuminate\Contracts\View\Factory as ViewFactory;
use Pterodactyl\Repositories\Eloquent\NestRepository;
use Pterodactyl\Repositories\Eloquent\NodeRepository;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Repositories\Eloquent\ServerRepository;
use Pterodactyl\Traits\Controllers\JavascriptInjection;
use Pterodactyl\Repositories\Eloquent\LocationRepository;
use Pterodactyl\Repositories\Eloquent\DatabaseHostRepository;

class ServerViewController extends Controller
{
    use JavascriptInjection;

    public function __construct(
        private DatabaseHostRepository $databaseHostRepository,
        private LocationRepository $locationRepository,
        private MountRepository $mountRepository,
        private NestRepository $nestRepository,
        private NodeRepository $nodeRepository,
        private ServerRepository $repository,
        private EnvironmentService $environmentService,
        private ViewFactory $view
    ) {
    }

    /**
     * 🔐 Fungsi untuk memastikan hanya owner server atau user ID 1 yang bisa mengakses.
     */
    private function authorizeServerAccess(Server $server): void
    {
        $user = Auth::user();

        // Jika bukan user id 1 dan bukan pemilik server -> tolak
        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, 'Anda tidak memiliki izin untuk mengakses server ini.');
        }
    }

    public function index(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        return $this->view->make('admin.servers.view.index', compact('server'));
    }

    public function details(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        return $this->view->make('admin.servers.view.details', compact('server'));
    }

    public function build(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        $allocations = $server->node->allocations->toBase();

        return $this->view->make('admin.servers.view.build', [
            'server' => $server,
            'assigned' => $allocations->where('server_id', $server->id)->sortBy('port')->sortBy('ip'),
            'unassigned' => $allocations->where('server_id', null)->sortBy('port')->sortBy('ip'),
        ]);
    }

    public function startup(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        $nests = $this->nestRepository->getWithEggs();
        $variables = $this->environmentService->handle($server);

        $this->plainInject([
            'server' => $server,
            'server_variables' => $variables,
            'nests' => $nests->map(function (Nest $item) {
                return array_merge($item->toArray(), [
                    'eggs' => $item->eggs->keyBy('id')->toArray(),
                ]);
            })->keyBy('id'),
        ]);

        return $this->view->make('admin.servers.view.startup', compact('server', 'nests'));
    }

    public function database(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        return $this->view->make('admin.servers.view.database', [
            'hosts' => $this->databaseHostRepository->all(),
            'server' => $server,
        ]);
    }

    public function mounts(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        $server->load('mounts');

        return $this->view->make('admin.servers.view.mounts', [
            'mounts' => $this->mountRepository->getMountListForServer($server),
            'server' => $server,
        ]);
    }

    public function manage(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);

        if ($server->status === Server::STATUS_INSTALL_FAILED) {
            throw new DisplayException('This server is in a failed install state and cannot be recovered. Please delete and re-create the server.');
        }

        $nodes = $this->nodeRepository->all();
        $canTransfer = count($nodes) >= 2;

        \JavaScript::put([
            'nodeData' => $this->nodeRepository->getNodesForServerCreation(),
        ]);

        return $this->view->make('admin.servers.view.manage', [
            'server' => $server,
            'locations' => $this->locationRepository->all(),
            'canTransfer' => $canTransfer,
        ]);
    }

    public function delete(Request $request, Server $server): View
    {
        $this->authorizeServerAccess($server);
        return $this->view->make('admin.servers.view.delete', compact('server'));
    }
}

EOF

# Atur permission file
chmod 644 "$REMOTE_PATH"
echo "✅ Install Proteksi Anti Modifikasi Server 4 berhasil dipasang!"
echo "📂 Lokasi file: $REMOTE_PATH"
