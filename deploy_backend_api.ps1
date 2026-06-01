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

$files = @(
    @{Local="backend_api\public\index.php";                      Remote="$RemoteBase/public/index.php"},
    @{Local="backend_api\src\repository.php";                    Remote="$RemoteBase/src/repository.php"},
    @{Local="backend_api\src\auth.php";                          Remote="$RemoteBase/src/auth.php"},
    @{Local="backend_api\public\_route.php";                     Remote="$RemoteBase/public/_route.php"},
    @{Local="backend_api\public\projects.php";                   Remote="$RemoteBase/public/projects.php"},
    @{Local="backend_api\public\projects_create.php";            Remote="$RemoteBase/public/projects_create.php"},
    @{Local="backend_api\public\projects_update.php";            Remote="$RemoteBase/public/projects_update.php"},
    @{Local="backend_api\public\projects_delete.php";            Remote="$RemoteBase/public/projects_delete.php"},
    @{Local="backend_api\public\projects_set_groups.php";        Remote="$RemoteBase/public/projects_set_groups.php"},
    @{Local="backend_api\public\family_groups.php";              Remote="$RemoteBase/public/family_groups.php"},
    @{Local="backend_api\public\family_groups_create.php";       Remote="$RemoteBase/public/family_groups_create.php"},
    @{Local="backend_api\public\family_groups_update.php";       Remote="$RemoteBase/public/family_groups_update.php"},
    @{Local="backend_api\public\family_groups_delete.php";       Remote="$RemoteBase/public/family_groups_delete.php"}
)

if ($DryRun) {
    Write-Host "=== DRY RUN ==="
    foreach ($f in $files) {
        Write-Host "Would upload: $($f.Local) -> $($f.Remote)"
    }
    exit 0
}

Write-Host "Deploying backend_api to $HostIp ..."

$script = @"
import paramiko, sys, os

host = os.environ["WEATHER_VPS_HOST"]
user = os.environ["WEATHER_VPS_USER"]
password = os.environ["WEATHER_VPS_PASSWORD"]
api_key = os.environ["TODO_BACKEND_API_KEY"]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username=user, password=password, timeout=15)
sftp = client.open_sftp()

files = [
$($files | ForEach-Object { "    ('$($_.Local)', '$($_.Remote)')," }) 
]

for local, remote in files:
    local_path = os.path.join(r'C:\Users\user\Desktop\weather', local)
    if not os.path.exists(local_path):
        print(f'  SKIP (not found): {local}')
        continue
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
    sftp.put(local_path, remote)
    print(f'  OK: {local} -> {remote}')

sftp.close()

# Test the endpoints
stdin, stdout, stderr = client.exec_command(f'curl -s -o /dev/null -w "%{{http_code}}" -X POST http://localhost/projects/create -H "Content-Type: application/json" -H "X-Api-Key: {api_key}" -d \'{{"actor_profile":"nik","name":"test"}}\' 2>&1')
print('Test /projects/create:', stdout.read().decode().strip())

stdin, stdout, stderr = client.exec_command(f'curl -s -o /dev/null -w "%{{http_code}}" -X POST http://localhost/family-groups/create -H "Content-Type: application/json" -H "X-Api-Key: {api_key}" -d \'{{"actor_profile":"nik","name":"test_group","members":["nik"]}}\' 2>&1')
print('Test /family-groups/create:', stdout.read().decode().strip())

client.close()
print('Deploy done.')
"@

$script | python -
