$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherScript = Join-Path $ProjectRoot 'bridge_launcher_watchdog.ps1'
$TaskName = 'BridgeLauncherAtLogon'

if (-not (Test-Path -LiteralPath $LauncherScript)) {
    throw "Launcher script not found: $LauncherScript"
}

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherScript`""

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
        -Description 'Keeps project bridge launcher available for mobile project chats.' `
        -Force | Out-Null
} catch {
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherScript`""
    & cmd.exe /c "schtasks.exe /Create /TN `"$TaskName`" /SC ONLOGON /TR `"$taskCommand`" /F >nul 2>nul"
}

$registeredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $registeredTask) {
    $startupDir = [Environment]::GetFolderPath('Startup')
    if (-not $startupDir) {
        throw "Failed to register scheduled task and Startup folder is unavailable"
    }
    New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
    $startupCmd = Join-Path $startupDir "$TaskName.cmd"
    @"
@echo off
cd /d "$ProjectRoot"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$LauncherScript"
"@ | Set-Content -Path $startupCmd -Encoding ascii
}

Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessName -like 'powershell*' -and
        $_.CommandLine -like '*bridge_launcher_watchdog.ps1*'
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
            $_.CommandLine -like '*bridge_launcher_watchdog.ps1*'
        } |
        Select-Object -First 1
    if (-not $watchdog) {
        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $LauncherScript) `
            -WindowStyle Hidden
    }
}
Start-Sleep -Seconds 2

Get-CimInstance Win32_Process |
    Where-Object {
        ($_.ProcessName -like 'python*' -and $_.CommandLine -like '*bridge_launcher.py*') -or
        ($_.ProcessName -like 'powershell*' -and $_.CommandLine -like '*bridge_launcher_watchdog.ps1*')
    } |
    Select-Object ProcessId, CommandLine
