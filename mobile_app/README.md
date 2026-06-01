# Family ToDo Mobile

Android-first Flutter app with offline sync, Telegram bridge, and FCM push.

Core client architecture is shared for mobile and desktop:
- local DB as source of truth,
- `SyncService` for push + pull snapshot/delta,
- shared domain/repository/state layers (`lib/domain`, `lib/repositories`, `lib/state`).

## Desktop (Windows) build

The same Flutter client is used for desktop migration.

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter pub get
flutter build windows --release ^
  --dart-define=API_BASE_URL=https://familly.nikportfolio.ru/backend_api/public ^
  --dart-define=API_KEY=YOUR_API_KEY ^
  --dart-define=FIREBASE_APP_ID=YOUR_FIREBASE_APP_ID ^
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_FIREBASE_SENDER_ID ^
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY ^
  --dart-define=FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET
```

Output executable:
`build\windows\x64\runner\Release\family_todo_mobile.exe`

## Install for family (simple)

1. Open the latest release link on phone.
2. Download `family-todo-release.apk`.
3. Install APK (allow install from browser once).
4. Next updates: download and install new APK over old one.

Latest APK link:
`https://github.com/Nikita-Tikhomirov/weather/releases/latest/download/family-todo-release.apk`

## Build pipeline

APK is built automatically by GitHub Actions workflow:
`.github/workflows/mobile-apk.yml`

Workflow does:
- prepares a full Flutter Android structure,
- restores project `lib/` and `pubspec.yaml`,
- builds release APK,
- publishes APK to GitHub Release.

Last CI trigger: 2026-04-22

## Local run (for development)

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://familly.nikportfolio.ru/backend_api/public \
  --dart-define=API_KEY=YOUR_API_KEY \
  --dart-define=FIREBASE_APP_ID=YOUR_FIREBASE_APP_ID \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_FIREBASE_SENDER_ID \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY \
  --dart-define=FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET
```

## Local verification

PowerShell from `mobile_app/`:

```powershell
C:\Users\user\tools\flutter\bin\flutter.bat test --concurrency=1
C:\Users\user\tools\flutter\bin\flutter.bat analyze
```

Use `--concurrency=1` for the full local test suite, matching CI. Some
sqflite-based tests change the global database factory and can make a
parallel full run fail while individual suites still pass.
