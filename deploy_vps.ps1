# PowerShell deploy script for laravel_backend_vps to VPS
param(
    [switch]$DryRun,
    [switch]$SkipMigration,
    [switch]$SkipStickerImport,
    [switch]$SkipStickerAssets,
    [string]$HostIp = $(if ($env:WEATHER_VPS_HOST) { $env:WEATHER_VPS_HOST } else { "31.129.97.211" }),
    [string]$HostUser = $(if ($env:WEATHER_VPS_USER) { $env:WEATHER_VPS_USER } else { "root" }),
    [string]$HostPassword = $env:WEATHER_VPS_PASSWORD,
    [string]$RemoteBase = $(if ($env:WEATHER_VPS_REMOTE_BASE) { $env:WEATHER_VPS_REMOTE_BASE } else { "/var/www/adebechigef" })
)

$ErrorActionPreference = "Stop"

if (-not $DryRun -and [string]::IsNullOrWhiteSpace($HostPassword)) {
    throw "Set WEATHER_VPS_PASSWORD or pass -HostPassword before deploying."
}

$env:WEATHER_VPS_HOST = $HostIp
$env:WEATHER_VPS_USER = $HostUser
$env:WEATHER_VPS_PASSWORD = $HostPassword
$env:WEATHER_VPS_REMOTE_BASE = $RemoteBase
$env:WEATHER_SKIP_MIGRATION = if ($SkipMigration) { "1" } else { "0" }
$env:WEATHER_SKIP_STICKER_IMPORT = if ($SkipStickerImport) { "1" } else { "0" }
$env:WEATHER_SKIP_STICKER_ASSETS = if ($SkipStickerAssets) { "1" } else { "0" }

$files = @(
    @{Local="laravel_backend_vps\config\sync.php"; Remote="$RemoteBase/config/sync.php"},
    @{Local="laravel_backend_vps\app\Domain\Access\AccessPolicyService.php"; Remote="$RemoteBase/app/Domain/Access/AccessPolicyService.php"},
    @{Local="laravel_backend_vps\app\Domain\Agent\AgentTaskService.php"; Remote="$RemoteBase/app/Domain/Agent/AgentTaskService.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\AgentPolicyController.php"; Remote="$RemoteBase/app/Http/Controllers/AgentPolicyController.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\AuthController.php"; Remote="$RemoteBase/app/Http/Controllers/AuthController.php"},
    @{Local="laravel_backend_vps\app\Services\Push\FcmPushGateway.php";   Remote="$RemoteBase/app/Services/Push/FcmPushGateway.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\ChatController.php"; Remote="$RemoteBase/app/Http/Controllers/ChatController.php"},
    @{Local="laravel_backend_vps\app\Domain\Chat\ChatRepository.php";      Remote="$RemoteBase/app/Domain/Chat/ChatRepository.php"},
    @{Local="laravel_backend_vps\app\Services\Push\PushOutboxService.php"; Remote="$RemoteBase/app/Services/Push/PushOutboxService.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_05_21_000700_add_avatar_url_to_messenger_users.php"; Remote="$RemoteBase/database/migrations/2026_05_21_000700_add_avatar_url_to_messenger_users.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\ProjectGroupController.php"; Remote="$RemoteBase/app/Http/Controllers/ProjectGroupController.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\SyncController.php";      Remote="$RemoteBase/app/Http/Controllers/SyncController.php"},
    @{Local="laravel_backend_vps\app\Domain\Sync\SyncRules.php";           Remote="$RemoteBase/app/Domain/Sync/SyncRules.php"},
    @{Local="laravel_backend_vps\app\Domain\Sync\SyncRepository.php";      Remote="$RemoteBase/app/Domain/Sync/SyncRepository.php"},
    @{Local="laravel_backend_vps\app\Domain\Sync\Profiles.php";            Remote="$RemoteBase/app/Domain/Sync/Profiles.php"},
    @{Local="laravel_backend_vps\app\Domain\Sync\ActorProfileGuard.php";   Remote="$RemoteBase/app/Domain/Sync/ActorProfileGuard.php"},
    @{Local="laravel_backend_vps\routes\api.php";                          Remote="$RemoteBase/routes/api.php"},
    @{Local="laravel_backend_vps\routes\console.php";                      Remote="$RemoteBase/routes/console.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_06_04_001000_create_access_and_agent_orchestration_tables.php"; Remote="$RemoteBase/database/migrations/2026_06_04_001000_create_access_and_agent_orchestration_tables.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_06_08_001100_create_project_control_center_tables.php"; Remote="$RemoteBase/database/migrations/2026_06_08_001100_create_project_control_center_tables.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_06_02_000700_deactivate_legacy_chat_stickers.php"; Remote="$RemoteBase/database/migrations/2026_06_02_000700_deactivate_legacy_chat_stickers.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_05_26_000800_add_projects_and_family_groups.php"; Remote="$RemoteBase/database/migrations/2026_05_26_000800_add_projects_and_family_groups.php"}
)

if ($DryRun) {
    Write-Host "=== DRY RUN ==="
    foreach ($f in $files) {
        Write-Host "Would upload: $($f.Local) -> $($f.Remote)"
    }
    if ($SkipMigration) {
        Write-Host "Would skip migration"
    } else {
        Write-Host "Would run: php artisan migrate --force"
    }
    if ($SkipStickerAssets) {
        Write-Host "Would skip sticker asset upload"
    } else {
        Write-Host "Would upload: assets\stickers\library -> $RemoteBase/assets/stickers/library"
        Write-Host "Would upload: assets\stickers\library_v2 -> $RemoteBase/assets/stickers/library_v2"
    }
    if ($SkipStickerImport) {
        Write-Host "Would skip sticker import"
    } else {
        Write-Host "Would run: php artisan chat:stickers-import assets/stickers"
    }
    Write-Host "Would run: php artisan cache:clear"
    exit 0
}

Write-Host "Checking Python + paramiko..."
python -c "import paramiko" 2>$null
if ($LASTEXITCODE -ne 0) {
    python -m pip install paramiko -q
}

$script = @"
import paramiko, sys, os

host = os.environ["WEATHER_VPS_HOST"]
user = os.environ["WEATHER_VPS_USER"]
password = os.environ["WEATHER_VPS_PASSWORD"]
remote_base = os.environ["WEATHER_VPS_REMOTE_BASE"]
skip_migration = os.environ.get("WEATHER_SKIP_MIGRATION") == "1"
skip_sticker_import = os.environ.get("WEATHER_SKIP_STICKER_IMPORT") == "1"
skip_sticker_assets = os.environ.get("WEATHER_SKIP_STICKER_ASSETS") == "1"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

files = [
$($files | ForEach-Object { $l = $_.Local -replace '\\', '/'; "    ('$l', '$($_.Remote)')," }) 
]

def ensure_remote_dir(path):
    parts = [part for part in path.strip('/').split('/') if part]
    current = ''
    for part in parts:
        current += '/' + part
        try:
            sftp.stat(current)
        except:
            sftp.mkdir(current)

for local, remote in files:
    print(f'Uploading {local} ...')
    # backup
    try:
        sftp.stat(remote + '.bak')
        sftp.remove(remote + '.bak')
    except:
        pass
    try:
        sftp.rename(remote, remote + '.bak')
    except:
        pass
    sftp.put(local, remote)
    print(f'  {local} -> {remote}')

def upload_tree(local_root, remote_root):
    if not os.path.isdir(local_root):
        print(f'Skip missing tree: {local_root}')
        return
    count = 0
    for base, _, names in os.walk(local_root):
        rel = os.path.relpath(base, local_root).replace('\\\\', '/')
        remote_dir = remote_root if rel == '.' else remote_root.rstrip('/') + '/' + rel
        ensure_remote_dir(remote_dir)
        for name in names:
            if name == '.gitkeep':
                continue
            local_path = os.path.join(base, name)
            remote_path = remote_dir.rstrip('/') + '/' + name
            sftp.put(local_path, remote_path)
            count += 1
            if count % 50 == 0:
                print(f'  uploaded sticker assets: {count}')
    print(f'Sticker assets uploaded: {count}')

if skip_sticker_assets:
    print('Sticker asset upload: skipped')
else:
    upload_tree('assets/stickers/library', f'{remote_base}/assets/stickers/library')
    upload_tree('assets/stickers/library_v2', f'{remote_base}/assets/stickers/library_v2')

sftp.close()

stdin0, stdout0, stderr0 = client.exec_command(f'cd {remote_base} && php artisan optimize:clear 2>&1')
print('Optimize clear:', stdout0.read().decode().strip())
err0 = stderr0.read().decode().strip()
if err0:
    print('Optimize clear stderr:', err0)

if skip_migration:
    print("Migration: skipped")
else:
    stdin, stdout, stderr = client.exec_command(f'cd {remote_base} && php artisan migrate --force 2>&1')
    print('Migration:', stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print('Migration stderr:', err)

if skip_sticker_import:
    print("Sticker import: skipped")
else:
    stdin3, stdout3, stderr3 = client.exec_command(f'cd {remote_base} && php artisan chat:stickers-import assets/stickers 2>&1')
    print('Sticker import:', stdout3.read().decode().strip())
    err3 = stderr3.read().decode().strip()
    if err3:
        print('Sticker import stderr:', err3)

stdin2, stdout2, stderr2 = client.exec_command(f'cd {remote_base} && php artisan cache:clear 2>&1')
print('Cache clear:', stdout2.read().decode().strip())

client.close()
print('Deploy done.')
"@

$script | python -
