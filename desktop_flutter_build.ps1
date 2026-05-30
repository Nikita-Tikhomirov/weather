param(
    [string]$ApiBaseUrl = "http://31.129.97.211",
    [string]$ApiKey = "dev-local-key",
    [string]$FirebaseAppId = "1:223906415067:android:68a62bb31cc4471895a7fe",
    [string]$FirebaseProjectId = "famillytodo-2758f",
    [string]$FirebaseSenderId = "223906415067",
    [string]$FirebaseApiKey = "AIzaSyBtO5Nbcb91lk3WViNIHzwYX_5yazfG6K8",
    [string]$FirebaseStorageBucket = "famillytodo-2758f.firebasestorage.app"
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
        --dart-define=API_KEY=$ApiKey `
        --dart-define=FIREBASE_APP_ID=$FirebaseAppId `
        --dart-define=FIREBASE_PROJECT_ID=$FirebaseProjectId `
        --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FirebaseSenderId `
        --dart-define=FIREBASE_API_KEY=$FirebaseApiKey `
        --dart-define=FIREBASE_STORAGE_BUCKET=$FirebaseStorageBucket

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
