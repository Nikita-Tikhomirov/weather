$ErrorActionPreference = 'SilentlyContinue'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $ProjectRoot '.deepseek\state'
$WatchdogLog = Join-Path $StateDir 'bridge_launcher_watchdog.log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-WatchdogLog {
    param([string]$Message)
    "$(Get-Date -Format o) $Message" |
        Out-File -FilePath $WatchdogLog -Encoding utf8 -Append
}

Write-WatchdogLog 'legacy project bridge watchdog is retired; holding process to prevent scheduled-task popup loops'

while ($true) {
    Start-Sleep -Seconds 3600
}
