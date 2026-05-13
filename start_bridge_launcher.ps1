$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $ProjectRoot '.deepseek\state'
$OutLog = Join-Path $StateDir 'bridge_launcher.log'
$ErrLog = Join-Path $StateDir 'bridge_launcher.err.log'
$Tunnel = '31.129.97.211:9877'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

$existing = Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessName -like 'python*' -and
        $_.CommandLine -like '*bridge_launcher.py*' -and
        $_.CommandLine -like "*$Tunnel*"
    } |
    Select-Object -First 1

if ($existing) {
    exit 0
}

Start-Process `
    -FilePath 'python' `
    -ArgumentList @('bridge_launcher.py', '--tunnel', $Tunnel) `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -WindowStyle Hidden
