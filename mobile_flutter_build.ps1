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
        --dart-define=API_KEY=$ApiKey `
        --dart-define=FIREBASE_APP_ID=$FirebaseAppId `
        --dart-define=FIREBASE_PROJECT_ID=$FirebaseProjectId `
        --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FirebaseSenderId `
        --dart-define=FIREBASE_API_KEY=$FirebaseApiKey `
        --dart-define=FIREBASE_STORAGE_BUCKET=$FirebaseStorageBucket

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
