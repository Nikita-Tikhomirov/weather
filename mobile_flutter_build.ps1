param(
    [string]$ApiBaseUrl = "http://31.129.97.211",
    [string]$ApiKey = "dev-local-key"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterAppDir = Join-Path $projectRoot "mobile_app"
$outputApk = Join-Path $flutterAppDir "build\app\outputs\flutter-apk\app-release.apk"
$flutterCmd = "flutter"
if (-not (Get-Command $flutterCmd -ErrorAction SilentlyContinue)) {
    $knownFlutter = "C:\Users\user\tools\flutter\bin\flutter.bat"
    if (Test-Path $knownFlutter) {
        $flutterCmd = $knownFlutter
    } else {
        throw "Flutter SDK not found. Install Flutter or add flutter to PATH."
    }
}

Write-Host "[flutter-android] Project: $flutterAppDir"
Push-Location $flutterAppDir
try {
    & $flutterCmd pub get
    & $flutterCmd build apk --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=API_KEY=$ApiKey

    if (-not (Test-Path $outputApk)) {
        throw "Flutter build finished without APK. Check Android SDK/NDK and signing setup."
    }

    Write-Host ""
    Write-Host "Done."
    Write-Host "APK: $outputApk"
}
finally {
    Pop-Location
}
