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
    # Fast path: check running processes first
    $fast = Get-Process -Name 'python*' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $cmd = $_.MainModule.FileName
                return $cmd -like '*python*'
            } catch {
                return $false
            }
        }

    # Fallback: check via CIM for full command line match
    $cim = Get-CimInstance Win32_Process |
        Where-Object {
            $_.ProcessName -like 'python*' -and
            $_.CommandLine -like '*codewhale_bridge.py*' -and
            $_.CommandLine -like "*$Tunnel*"
        } |
        Select-Object -First 1

    return $cim
}

try {
    while ($true) {
        try {
            $bridge = Get-CodeWhaleBridgeProcess
            if (-not $bridge) {
                Write-WatchdogLog 'codewhale_bridge process missing; starting'
                powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$BridgeScript"
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
