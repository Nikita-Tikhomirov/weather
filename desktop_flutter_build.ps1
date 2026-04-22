param(
    [string]$ApiBaseUrl = "https://familly.nikportfolio.ru/backend_api/public",
    [string]$ApiKey = "dev-local-key"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterAppDir = Join-Path $projectRoot "mobile_app"
$outputExe = Join-Path $flutterAppDir "build\windows\x64\runner\Release\family_todo_mobile.exe"
$flutterCmd = "flutter"
if (-not (Get-Command $flutterCmd -ErrorAction SilentlyContinue)) {
    $knownFlutter = "C:\Users\user\tools\flutter\bin\flutter.bat"
    if (Test-Path $knownFlutter) {
        $flutterCmd = $knownFlutter
    } else {
        throw "Flutter SDK not found. Install Flutter or add flutter to PATH."
    }
}

Write-Host "[flutter-desktop] Project: $flutterAppDir"
Push-Location $flutterAppDir
try {
    & $flutterCmd config --enable-windows-desktop | Out-Null
    & $flutterCmd pub get
    & $flutterCmd build windows --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=API_KEY=$ApiKey

    if (-not (Test-Path $outputExe)) {
        throw "Flutter build finished without EXE. Usually this means Windows Developer Mode (symlink support) is disabled."
    }

    Write-Host ""
    Write-Host "Done."
    Write-Host "EXE: $outputExe"
}
finally {
    Pop-Location
}
