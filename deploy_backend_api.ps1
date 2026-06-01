# Deploy backend_api (simple PHP) to VPS
param(
    [switch]$DryRun,
    [string]$HostIp = $(if ($env:WEATHER_VPS_HOST) { $env:WEATHER_VPS_HOST } else { "31.129.97.211" }),
    [string]$HostUser = $(if ($env:WEATHER_VPS_USER) { $env:WEATHER_VPS_USER } else { "root" }),
    [string]$HostPassword = $env:WEATHER_VPS_PASSWORD,
    [string]$RemoteBase = $(if ($env:WEATHER_SIMPLE_API_REMOTE_BASE) { $env:WEATHER_SIMPLE_API_REMOTE_BASE } else { "/var/www/html" }),
    [string]$ApiKey = $(if ($env:TODO_BACKEND_API_KEY) { $env:TODO_BACKEND_API_KEY } else { "dev-local-key" })
)

$ErrorActionPreference = "Stop"

if (-not $DryRun -and [string]::IsNullOrWhiteSpace($HostPassword)) {
    throw "Set WEATHER_VPS_PASSWORD or pass -HostPassword before deploying."
}

# The simple PHP backend is served directly from this path.
$env:WEATHER_VPS_HOST = $HostIp
$env:WEATHER_VPS_USER = $HostUser
$env:WEATHER_VPS_PASSWORD = $HostPassword
$env:WEATHER_SIMPLE_API_REMOTE_BASE = $RemoteBase
$env:TODO_BACKEND_API_KEY = $ApiKey

$files = @()
foreach ($dir in @("public", "src")) {
    Get-ChildItem -Path "backend_api\$dir" -Filter "*.php" | ForEach-Object {
        $files += @{
            Local = ($_.FullName.Substring((Resolve-Path ".").Path.Length + 1) -replace "\\", "/")
            Remote = "$RemoteBase/$dir/$($_.Name)"
        }
    }
}

if ($DryRun) {
    Write-Host "=== DRY RUN ==="
    foreach ($f in $files) {
        Write-Host "Would upload: $($f.Local) -> $($f.Remote)"
    }
    exit 0
}

Write-Host "Deploying backend_api to $HostIp ..."

$script = @"
import paramiko, sys, os, posixpath

host = os.environ["WEATHER_VPS_HOST"]
user = os.environ["WEATHER_VPS_USER"]
password = os.environ["WEATHER_VPS_PASSWORD"]
api_key = os.environ["TODO_BACKEND_API_KEY"]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

def ensure_remote_dir(path):
    parts = []
    current = path
    while current not in ('', '/'):
        parts.append(current)
        current = posixpath.dirname(current)
    for item in reversed(parts):
        try:
            sftp.stat(item)
        except FileNotFoundError:
            sftp.mkdir(item)

files = [
$($files | ForEach-Object { "    ('$($_.Local)', '$($_.Remote)')," }) 
]

for local, remote in files:
    local_path = os.path.join(r'C:\Users\user\Desktop\weather', local)
    if not os.path.exists(local_path):
        print(f'  SKIP (not found): {local}')
        continue
    print(f'Uploading {local} ...')
    ensure_remote_dir(posixpath.dirname(remote))
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
    sftp.put(local_path, remote)
    print(f'  OK: {local} -> {remote}')

remote_base = os.environ["WEATHER_SIMPLE_API_REMOTE_BASE"]
try:
    sftp.stat(posixpath.join(remote_base, 'config.php'))
    has_config = True
except FileNotFoundError:
    has_config = False

sftp.close()

if has_config:
    migration = r'''php <<'PHP'
<?php
`$config = require '__REMOTE_BASE__/config.php';
`$db = `$config['db'] ?? [];
`$dsn = sprintf(
    'mysql:host=%s;port=%d;dbname=%s;charset=%s',
    `$db['host'] ?? '127.0.0.1',
    (int)(`$db['port'] ?? 3306),
    `$db['name'] ?? '',
    `$db['charset'] ?? 'utf8mb4'
);
`$pdo = new PDO(`$dsn, `$db['user'] ?? '', `$db['pass'] ?? '', [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
foreach (['tasks', 'family_tasks'] as `$table) {
    `$stmt = `$pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    `$stmt->execute([`$table, 'collaboration_json']);
    if ((int)`$stmt->fetchColumn() === 0) {
        `$pdo->exec(sprintf('ALTER TABLE `%s` ADD COLUMN `collaboration_json` JSON NULL AFTER `participants_json`', `$table));
        echo "added `$table.collaboration_json\n";
    } else {
        echo "exists `$table.collaboration_json\n";
    }
}
PHP'''.replace('__REMOTE_BASE__', remote_base)
    stdin, stdout, stderr = client.exec_command(migration)
    print(stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print(err, file=sys.stderr)
        sys.exit(1)
else:
    print('Migration skipped: config.php not found, file-store sync mode is active.')

# Test the endpoints
stdin, stdout, stderr = client.exec_command(f'curl -s -o /dev/null -w "%{{http_code}}" -X POST http://localhost/projects/create -H "Content-Type: application/json" -H "X-Api-Key: {api_key}" -d \'{{"actor_profile":"nik","name":"test"}}\' 2>&1')
print('Test /projects/create:', stdout.read().decode().strip())

stdin, stdout, stderr = client.exec_command(f'curl -s -o /dev/null -w "%{{http_code}}" -X POST http://localhost/family-groups/create -H "Content-Type: application/json" -H "X-Api-Key: {api_key}" -d \'{{"actor_profile":"nik","name":"test_group","members":["nik"]}}\' 2>&1')
print('Test /family-groups/create:', stdout.read().decode().strip())

client.close()
print('Deploy done.')
"@

$script | python -
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
