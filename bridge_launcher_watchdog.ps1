$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherScript = Join-Path $ProjectRoot 'start_bridge_launcher.ps1'
$StateDir = Join-Path $ProjectRoot '.deepseek\state'
$WatchdogLog = Join-Path $StateDir 'bridge_launcher_watchdog.log'
$Tunnel = '31.129.97.211:9877'
$ProbeTimeoutMs = 5000

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-WatchdogLog {
    param([string]$Message)
    "$(Get-Date -Format o) $Message" |
        Out-File -FilePath $WatchdogLog -Encoding utf8 -Append
}

Write-WatchdogLog 'legacy project bridge watchdog is retired; CodeWhaleBridgeAtLogon owns mobile workspace sessions'
exit 0

$MutexName = 'Global\WeatherProjectBridgeLauncherWatchdog'
$CreatedNew = $false
$Mutex = [System.Threading.Mutex]::new($true, $MutexName, [ref]$CreatedNew)
if (-not $CreatedNew) {
    Write-WatchdogLog 'another watchdog instance is already running; exiting duplicate'
    exit 0
}

function Test-LauncherRegistered {
    $parts = $Tunnel.Split(':', 2)
    $hostName = $parts[0]
    $port = 9877
    if ($parts.Count -eq 2 -and $parts[1]) {
        $port = [int]$parts[1]
    }

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.BeginConnect($hostName, $port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($ProbeTimeoutMs)) {
            return $false
        }
        $client.EndConnect($connect)
        $client.ReceiveTimeout = $ProbeTimeoutMs
        $client.SendTimeout = $ProbeTimeoutMs

        $stream = $client.GetStream()
        $payload = '{"type":"launcher_ping","project_id":"launcher"}' + "`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()

        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            return $false
        }
        return $line -like '*"type": "status"*' -or $line -like '*"type":"status"*'
    } catch {
        Write-WatchdogLog "launcher probe failed: $($_.Exception.Message)"
        return $false
    } finally {
        $client.Close()
    }
}

function Stop-StaleLauncher {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.ProcessName -like 'python*' -and
            $_.CommandLine -like '*bridge_launcher.py*' -and
            $_.CommandLine -like "*$Tunnel*"
        } |
        ForEach-Object {
            try {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                Write-WatchdogLog "stopped stale bridge_launcher pid=$($_.ProcessId)"
            } catch {
                Write-WatchdogLog "failed to stop stale launcher pid=$($_.ProcessId): $($_.Exception.Message)"
            }
        }
}

try {
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
                Write-WatchdogLog "bridge_launcher process missing; starting"
                powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$LauncherScript"
            } elseif (-not (Test-LauncherRegistered)) {
                Write-WatchdogLog "bridge_launcher process exists but VPS has no active launcher; restarting"
                Stop-StaleLauncher
                powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$LauncherScript"
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
