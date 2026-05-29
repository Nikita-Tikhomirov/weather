$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WatchdogScript = Join-Path $ProjectRoot 'codewhale_bridge_watchdog.ps1'
$TaskName = 'CodeWhaleBridgeAtLogon'

if (-not (Test-Path -LiteralPath $WatchdogScript)) {
    throw "Watchdog script not found: $WatchdogScript"
}

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$WatchdogScript`""

$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn),
    (New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Days 3650))
)
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Days 30) `
    -MultipleInstances IgnoreNew `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1)

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $triggers `
        -Settings $settings `
        -Description 'Keeps CodeWhale mobile workspace bridge available after reboot and crashes.' `
        -Force | Out-Null
} catch {
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$WatchdogScript`""
    & cmd.exe /c "schtasks.exe /Create /TN `"$TaskName`" /SC ONLOGON /TR `"$taskCommand`" /F >nul 2>nul"
}

$registeredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $registeredTask) {
    $startupDir = [Environment]::GetFolderPath('Startup')
    if (-not $startupDir) {
        throw 'Failed to register scheduled task and Startup folder is unavailable'
    }
    New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
    $startupCmd = Join-Path $startupDir "$TaskName.cmd"
    @"
@echo off
cd /d "$ProjectRoot"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$WatchdogScript"
"@ | Set-Content -Path $startupCmd -Encoding ascii
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$WatchdogScript`""
try {
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty `
        -Path $runKey `
        -Name $TaskName `
        -Value $runCommand `
        -PropertyType String `
        -Force | Out-Null
} catch {
}

Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessName -like 'powershell*' -and
        $_.CommandLine -like '*codewhale_bridge_watchdog.ps1*'
    } |
    ForEach-Object {
        try {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        } catch {
        }
    }

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
} catch {
    $watchdog = Get-CimInstance Win32_Process |
        Where-Object {
            $_.ProcessName -like 'powershell*' -and
            $_.CommandLine -like '*codewhale_bridge_watchdog.ps1*'
        } |
        Select-Object -First 1
    if (-not $watchdog) {
        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $WatchdogScript) `
            -WindowStyle Hidden
    }
}
Start-Sleep -Seconds 2

Get-CimInstance Win32_Process |
    Where-Object {
        ($_.ProcessName -like 'python*' -and $_.CommandLine -like '*codewhale_bridge.py*') -or
        ($_.ProcessName -like 'powershell*' -and $_.CommandLine -like '*codewhale_bridge_watchdog.ps1*')
    } |
    Select-Object ProcessId, CommandLine
