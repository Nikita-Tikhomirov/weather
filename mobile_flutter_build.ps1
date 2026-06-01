param(
    [string]$ApiBaseUrl = $(if ($env:API_BASE_URL) { $env:API_BASE_URL } elseif ($env:MOBILE_API_BASE_URL) { $env:MOBILE_API_BASE_URL } else { "http://31.129.97.211" }),
    [string]$ApiKey = $(if ($env:API_KEY) { $env:API_KEY } elseif ($env:TODO_BACKEND_API_KEY) { $env:TODO_BACKEND_API_KEY } else { "dev-local-key" }),
    [string]$FirebaseAppId = $env:FIREBASE_APP_ID,
    [string]$FirebaseProjectId = $env:FIREBASE_PROJECT_ID,
    [string]$FirebaseSenderId = $env:FIREBASE_MESSAGING_SENDER_ID,
    [string]$FirebaseApiKey = $env:FIREBASE_API_KEY,
    [string]$FirebaseStorageBucket = $env:FIREBASE_STORAGE_BUCKET,
    [string]$TurnUrls = $(if ($env:TURN_URLS) { $env:TURN_URLS } else { "turn:31.129.97.211:3478?transport=udp,turn:31.129.97.211:3478?transport=tcp" }),
    [string]$TurnUsername = $(if ($env:TURN_USERNAME) { $env:TURN_USERNAME } else { "family" }),
    [string]$TurnCredential = $(if ($env:TURN_CREDENTIAL) { $env:TURN_CREDENTIAL } else { "dev-turn-credential" }),
    [string]$BridgeDefaultHost = $(if ($env:BRIDGE_DEFAULT_HOST) { $env:BRIDGE_DEFAULT_HOST } else { "31.129.97.211:9877" })
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
$previousBuildEnv = @{
    API_BASE_URL = $env:API_BASE_URL
    API_KEY = $env:API_KEY
}
try {
    $env:API_BASE_URL = $ApiBaseUrl
    $env:API_KEY = $ApiKey
    & $flutterCmd pub get
    & $flutterCmd build apk --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=API_KEY=$ApiKey `
        --dart-define=FIREBASE_APP_ID=$FirebaseAppId `
        --dart-define=FIREBASE_PROJECT_ID=$FirebaseProjectId `
        --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FirebaseSenderId `
        --dart-define=FIREBASE_API_KEY=$FirebaseApiKey `
        --dart-define=FIREBASE_STORAGE_BUCKET=$FirebaseStorageBucket `
        --dart-define=TURN_URLS=$TurnUrls `
        --dart-define=TURN_USERNAME=$TurnUsername `
        --dart-define=TURN_CREDENTIAL=$TurnCredential `
        --dart-define=BRIDGE_DEFAULT_HOST=$BridgeDefaultHost

    if (-not (Test-Path $outputApk)) {
        throw "Flutter build finished without APK. Check Android SDK/NDK and signing setup."
    }

    Write-Host ""
    Write-Host "Done."
    Write-Host "APK: $outputApk"
}
finally {
    $env:API_BASE_URL = $previousBuildEnv.API_BASE_URL
    $env:API_KEY = $previousBuildEnv.API_KEY
    Pop-Location
}
