param(
    [string]$ApiBaseUrl = "https://familly.nikportfolio.ru/backend_api/public",
    [string]$ApiKey = "dev-local-key"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterAppDir = Join-Path $projectRoot "mobile_app"

Write-Host "[flutter-desktop] Project: $flutterAppDir"
Push-Location $flutterAppDir
try {
    flutter config --enable-windows-desktop | Out-Null
    flutter pub get
    flutter build windows --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=API_KEY=$ApiKey

    Write-Host ""
    Write-Host "Done."
    Write-Host "EXE: .\mobile_app\build\windows\x64\runner\Release\family_todo_mobile.exe"
}
finally {
    Pop-Location
}
