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
  --dart-define=API_KEY=YOUR_API_KEY
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

## Local run (for development)

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://familly.nikportfolio.ru/backend_api/public \
  --dart-define=API_KEY=YOUR_API_KEY
```
