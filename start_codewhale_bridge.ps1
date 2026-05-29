$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $ProjectRoot '.codewhale_bridge'
$OutLog = Join-Path $StateDir 'codewhale_bridge.log'
$ErrLog = Join-Path $StateDir 'codewhale_bridge.err.log'
$Tunnel = '31.129.97.211:9877'
$DesktopRoot = Join-Path $env:USERPROFILE 'Desktop'

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

    throw 'Python executable was not found for CodeWhale bridge autostart.'
}

$existing = Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessName -like 'python*' -and
        $_.CommandLine -like '*codewhale_bridge.py*' -and
        $_.CommandLine -like "*$Tunnel*"
    } |
    Select-Object -First 1

if ($existing) {
    exit 0
}

$PythonExe = Resolve-PythonExe

Start-Process `
    -FilePath $PythonExe `
    -ArgumentList @(
        'codewhale_bridge.py',
        '--tunnel', $Tunnel,
        '--desktop', $DesktopRoot,
        '--state-dir', $StateDir,
        '--project-id', 'codewhale'
    ) `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -WindowStyle Hidden
