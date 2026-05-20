# PowerShell deploy script for laravel_backend_vps to VPS
param(
    [switch]$DryRun,
    [switch]$SkipMigration
)

$hostIp = "31.129.97.211"
$hostUser = "root"
$hostPassword = "WCw8eJo&TIxu"
$remoteBase = "/var/www/adebechigef"

$files = @(
    @{Local="laravel_backend_vps\app\Services\Push\FcmPushGateway.php";   Remote="$remoteBase/app/Services/Push/FcmPushGateway.php"},
    @{Local="laravel_backend_vps\app\Http\Controllers\ChatController.php"; Remote="$remoteBase/app/Http/Controllers/ChatController.php"},
    @{Local="laravel_backend_vps\app\Domain\Chat\ChatRepository.php";      Remote="$remoteBase/app/Domain/Chat/ChatRepository.php"},
    @{Local="laravel_backend_vps\app\Services\Push\PushOutboxService.php"; Remote="$remoteBase/app/Services/Push/PushOutboxService.php"},
    @{Local="laravel_backend_vps\database\migrations\2026_05_21_000700_add_avatar_url_to_messenger_users.php"; Remote="$remoteBase/database/migrations/2026_05_21_000700_add_avatar_url_to_messenger_users.php"}
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

host = "$hostIp"
user = "$hostUser"
password = "$hostPassword"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

files = [
$($files | ForEach-Object { "    ('$($_.Local)', '$($_.Remote)')," }) 
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

$migrationCmd = "#migration"
if ("$SkipMigration" -ne "True") {
    $migrationCmd = ""
}

stdin, stdout, stderr = client.exec_command(f'cd $remoteBase && php artisan migrate --force 2>&1 $migrationCmd')
print('Migration:', stdout.read().decode().strip())
err = stderr.read().decode().strip()
if err:
    print('Migration stderr:', err)

stdin2, stdout2, stderr2 = client.exec_command(f'cd $remoteBase && php artisan cache:clear 2>&1')
print('Cache clear:', stdout2.read().decode().strip())

client.close()
print('Deploy done.')
"@

$script | python -
