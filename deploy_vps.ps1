# PowerShell deploy script for laravel_backend_vps to VPS
param(
    [switch]$DryRun,
    [switch]$SkipMigration,
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

$files = @(
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
    @{Local="laravel_backend_vps\database\migrations\2026_05_26_000800_add_projects_and_family_groups.php"; Remote="$RemoteBase/database/migrations/2026_05_26_000800_add_projects_and_family_groups.php"}
)

if ($DryRun) {
    Write-Host "=== DRY RUN ==="
    foreach ($f in $files) {
        Write-Host "Would upload: $($f.Local) -> $($f.Remote)"
    }
    Write-Host "Would run: php artisan migrate --force"
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

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

files = [
$($files | ForEach-Object { $l = $_.Local -replace '\\', '/'; "    ('$l', '$($_.Remote)')," }) 
]

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

sftp.close()

if skip_migration:
    print("Migration: skipped")
else:
    stdin, stdout, stderr = client.exec_command(f'cd {remote_base} && php artisan migrate --force 2>&1')
    print('Migration:', stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print('Migration stderr:', err)

stdin2, stdout2, stderr2 = client.exec_command(f'cd {remote_base} && php artisan cache:clear 2>&1')
print('Cache clear:', stdout2.read().decode().strip())

client.close()
print('Deploy done.')
"@

$script | python -
