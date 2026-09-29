# Platforms

## Web UI

Next.js app in `apps/web` (port `8000`, demo `8101`). All pages go through `DashboardApp` + login form; the browser talks to same-origin `/api/*` routes that proxy to the API (see [Architecture](ARCHITECTURE.md)). Covered in [Features](FEATURES.md).

## Android (`android/`)

Kotlin + Jetpack Compose (Material3), single activity + `NavGraph`, bottom bar (Home, Homework, Messages, Timetable, More), MVVM per feature, one Retrofit `ApiService` + DataStore `TokenStore` with Bearer interceptor, tolerant DTOs (`ignoreUnknownKeys`).

- **Screens**: onboarding/login + 2FA, homework (filter, trash, counters), messages (list/thread/compose, `?dl=` downloads, locally tracked unread), timetable (day/week, now-pill, cancellations), grades (average card, half-year chips, expandable subjects), settings + more (profile, appearance, weather, devices, server dialog, cache), home (live clock, now-card, weather), school day (agenda + substitutions).
- **Defaults**: `http://10.0.2.2:3000/api/v1/` (emulator loopback; demo `:3100`), changeable in Login/Settings without rebuild. Physical device: `http://<host-LAN-IP>:3000/api/v1/`.
- **Build & test** (Gradle is not on `PATH`):
  ```sh
  cd android
  <GRADLE-DIST>/gradle-8.7/bin/gradle :app:assembleDebug :app:testDebugUnitTest
  ```
  Offline unit tests with a fake `ApiService` (currently 79 tests).

## macOS (`mac/`)

Swift 5 + SwiftUI, macOS 14+, system frameworks only. Single entry + top pill nav in web design, onboarding window small and fixed then freely resizable, MVVM per feature, one `APIClient` (central Bearer) + file-based `TokenStore` (`0600` in Application Support — deliberately no Keychain, avoids dialogs with ad-hoc signing), string catalog localization.

- **Views**: auth (login/2FA/logout) + settings + devices, messages (list, thread with likes/replies, compose with recipient search), homework (filter, trash, done) + grades (average, subjects), timetable (day/week) + overview (clock, now/next, weather, latest), school day (agenda + substitutions).
- **Defaults**: same machine `http://127.0.0.1:3000` (demo `:3100`; loopback exception in `Info.plist`, sandbox + network entitlement).
- **Build & test**:
  ```sh
  cd mac
  xcodebuild -project "EduFlow Mac.xcodeproj" -scheme "EduFlow Mac" -destination 'platform=macOS' test
  ```
  Offline tests with per-route URL stubs (currently 89 tests). New files must be registered in `project.pbxproj` or they are “not in scope”.

## Status codes and 401 behavior (all platforms)

Status/type values (`offen`, `überfällig`, …) and the error `code` vocabulary are stable and never translated. On `401` (`TOKEN_INVALID/EXPIRED`, `EDUPAGE_2FA` → re-login) every client returns to login.
