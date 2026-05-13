$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherScript = Join-Path $ProjectRoot 'start_bridge_launcher.ps1'
$StateDir = Join-Path $ProjectRoot '.deepseek\state'
$WatchdogLog = Join-Path $StateDir 'bridge_launcher_watchdog.log'
$Tunnel = '31.129.97.211:9877'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

while ($true) {
    try {
        $launcher = Get-CimInstance Win32_Process |
            Where-Object {
                $_.ProcessName -like 'python*' -and
                $_.CommandLine -like '*bridge_launcher.py*' -and
                $_.CommandLine -like "*$Tunnel*"
            } |
            Select-Object -First 1

        if (-not $launcher) {
            "$(Get-Date -Format o) restarting bridge_launcher" |
                Out-File -FilePath $WatchdogLog -Encoding utf8 -Append
            powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$LauncherScript"
        }
    } catch {
        "$(Get-Date -Format o) watchdog error: $($_.Exception.Message)" |
            Out-File -FilePath $WatchdogLog -Encoding utf8 -Append
    }

    Start-Sleep -Seconds 15
}
