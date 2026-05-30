$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeScript = Join-Path $ProjectRoot 'start_codewhale_bridge.ps1'
$StateDir = Join-Path $ProjectRoot '.codewhale_bridge'
$WatchdogLog = Join-Path $StateDir 'codewhale_bridge_watchdog.log'
$Tunnel = '31.129.97.211:9877'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-WatchdogLog {
    param([string]$Message)
    "$(Get-Date -Format o) $Message" |
        Out-File -FilePath $WatchdogLog -Encoding utf8 -Append
}

$MutexName = 'Global\WeatherCodeWhaleBridgeWatchdog'
$CreatedNew = $false
$Mutex = [System.Threading.Mutex]::new($true, $MutexName, [ref]$CreatedNew)
if (-not $CreatedNew) {
    Write-WatchdogLog 'another watchdog instance is already running; exiting duplicate'
    exit 0
}

function Get-CodeWhaleBridgeProcess {
    $escapedProjectRoot = [Regex]::Escape($ProjectRoot)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -like 'python*' -and
            $_.CommandLine -like '*codewhale_bridge.py*' -and
            (
                $_.CommandLine -like "*$Tunnel*" -or
                $_.CommandLine -match $escapedProjectRoot
            )
        } |
        Select-Object -First 1
}

try {
    while ($true) {
        try {
            $bridge = Get-CodeWhaleBridgeProcess
            if (-not $bridge) {
                Write-WatchdogLog 'codewhale_bridge process missing; starting'
                Start-Process `
                    -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                    -ArgumentList @(
                        '-NoProfile',
                        '-NonInteractive',
                        '-ExecutionPolicy', 'Bypass',
                        '-WindowStyle', 'Hidden',
                        '-File', $BridgeScript
                    ) `
                    -WindowStyle Hidden `
                    -WorkingDirectory $ProjectRoot
            }
        } catch {
            Write-WatchdogLog "watchdog error: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 15
    }
} finally {
    $Mutex.ReleaseMutex() | Out-Null
    $Mutex.Dispose()
}
