#!/bin/bash

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/SystemInformationController.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "🚀 Install Proteksi Anti Modifikasi Detail Nodes 4..."

# Pastikan folder tujuan ada
mkdir -p "$(dirname "$REMOTE_PATH")"
chmod 755 "$(dirname "$REMOTE_PATH")"

# Tulis ulang file baru
cat > "$REMOTE_PATH" <<'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\Support\Str;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Node;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Repositories\Wings\DaemonConfigurationRepository;

class SystemInformationController extends Controller
{
    /**
     * SystemInformationController constructor.
     */
    public function __construct(private DaemonConfigurationRepository $repository)
    {
        // 🔒 Proteksi global controller ini
        $user = Auth::user();

        if (!$user || $user->id !== 1) {
            // Catat semua percobaan akses ilegal di log Laravel
            \Log::warning('🚨 Percobaan akses SystemInformationController tanpa izin', [
                'user_id' => $user?->id,
                'ip' => request()->ip(),
                'route' => request()->path(),
                'method' => request()->method(),
                'time' => now()->toDateTimeString(),
            ]);

            abort(403, 'Akses ditolak! Hanya admin ID 1 yang boleh mengakses System Information Nodes');
        }
    }

    /**
     * Returns system information from the Daemon.
     *
     * @throws \Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException
     */
    public function __invoke(Request $request, Node $node): JsonResponse
    {
        $data = $this->repository->setNode($node)->getSystemInformation();

        return new JsonResponse([
            'version' => $data['version'] ?? '',
            'system' => [
                'type' => Str::title($data['os'] ?? 'Unknown'),
                'arch' => $data['architecture'] ?? '--',
                'release' => $data['kernel_version'] ?? '--',
                'cpus' => $data['cpu_count'] ?? 0,
            ],
        ]);
    }
}

EOF

# Atur permission file
chmod 644 "$REMOTE_PATH"
echo "✅ Install Proteksi Anti Modifikasi Detail Nodes 4 berhasil dipasang!"
echo "📂 Lokasi file: $REMOTE_PATH"
