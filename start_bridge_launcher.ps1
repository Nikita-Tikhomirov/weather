$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $ProjectRoot '.deepseek\state'
$OutLog = Join-Path $StateDir 'bridge_launcher.log'
$ErrLog = Join-Path $StateDir 'bridge_launcher.err.log'
$Tunnel = '31.129.97.211:9877'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Resolve-PythonExe {
    if ($env:PYTHON -and (Test-Path -LiteralPath $env:PYTHON)) {
        return (Resolve-Path -LiteralPath $env:PYTHON).Path
    }

    $knownPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310\python.exe')
    )
    foreach ($path in $knownPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand -and $pythonCommand.Source) {
        return $pythonCommand.Source
    }

    $pyCommand = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCommand -and $pyCommand.Source) {
        $resolved = & $pyCommand.Source -3 -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $resolved -and (Test-Path -LiteralPath $resolved.Trim())) {
            return (Resolve-Path -LiteralPath $resolved.Trim()).Path
        }
    }

    throw 'Python executable was not found for bridge launcher autostart.'
}

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

$PythonExe = Resolve-PythonExe

Start-Process `
    -FilePath $PythonExe `
    -ArgumentList @('bridge_launcher.py', '--tunnel', $Tunnel) `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -WindowStyle Hidden
