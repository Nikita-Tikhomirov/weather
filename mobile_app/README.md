# Family ToDo Mobile

Android-first Flutter app with offline sync, Telegram bridge, and FCM push.

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
