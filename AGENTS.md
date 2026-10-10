# EduFlow — Agent Guide

## Project overview

EduFlow is a local school dashboard for EduPage. Its primary stack is a
Next.js web application, a NestJS JSON API, and native Android and macOS
clients. The server is intended for local use, not production deployment.

- **Backend:** NestJS in `apps/api`, normally on port 3000.
- **Web application:** Next.js in `apps/web`, normally on port 8000.
- **API base path:** `/api/v1`.
- **Shared contracts:** TypeScript package in `packages/`.
- **Native clients:** Android in `android/` and macOS in `mac/`.
- **iOS:** Existing implementation is on hold. Do not extend it without an
  explicit request.
- **Python:** The previous Python stack is archived and is not part of active
  development.

Prioritize Android, macOS, and the web application. Keep the API compatible
with existing clients.

## Repository layout

```text
apps/api/         NestJS API and EduPage/fake providers
apps/web/         Next.js web application
packages/         Shared TypeScript contracts
migration/        Installer scripts and migration documentation
static/icons/     Source application icon
android/          Kotlin and Jetpack Compose application
mac/              SwiftUI macOS application
ios/              SwiftUI iOS application (on hold)
```

The API supports two providers, selected with `EDUFLOW_PROVIDER`:

- `edupage` connects to EduPage using the configured login session.
- `fake` provides demo data and supports the demo account `demo` / `demo`.

Use `./run.sh` for the normal setup or `./run.sh --demo` for the demo setup.
Initial setup is handled by `./install.sh`. The setup uses PostgreSQL and
creates a local environment file with restricted permissions.

## Security and local data

- Never read, print, copy, or commit credentials, tokens, private keys,
  environment files, authentication data, database or vault credentials, or
  other secret material.
- Do not inspect cache contents, login state, or logs that may contain
  sensitive data.
- Tests and validation must use fake providers, fake clients, or URL stubs;
  never use real account credentials.
- Do not expose secrets, stack traces, or local filesystem paths in
  user-facing messages.
- Do not commit generated build output, including `build/`, `.gradle/`,
  `DerivedData/`, and `xcuserdata/`.
- Do not include real names, local machine paths, or hostnames in tracked
  files or commit messages.

## API compatibility

Treat existing `/api/v1` routes, response shapes, and DTOs as stable. The API
reference is available at `GET /api/v1/openapi.json`; `GET /api/v1/health`
does not require authentication.

- Authentication uses bearer tokens. The API also supports short-lived
  download tokens for file downloads.
- Two-factor authentication is a two-step flow: `auth/login` can return
  `2fa_required` with a `pending_token`; `auth/2fa` exchanges it for a full
  token. Pending tokens expire after 10 minutes.
- Login rate limiting is 20 requests per IP per 10 minutes.
- Errors use the `{error, code}` shape and canonical codes:
  `VALIDATION`, `TOKEN_INVALID`, `TOKEN_EXPIRED`, `PENDING_INVALID`,
  `INVALID_CODE`, `BAD_CREDENTIALS`, `EDUPAGE_2FA`, `CAPTCHA_REQUIRED`,
  `NOT_FOUND`, `RATE_LIMITED`, `CONFIG_MISSING`, and `UPSTREAM`.
- List responses use `{items, total, limit, offset}`. The default limit is
  50 and the maximum is 200.
- Keep shared DTOs aligned with the web dictionaries and the native clients.
- Additive routes are acceptable when existing routes and response shapes
  remain compatible. Justify new backend dependencies.
- A 401 response caused by an invalid or expired token, or by EduPage
  two-factor requirements, should return the user to login.

School-day data includes substitutions at `substitutions/week` and calendar,
exam, and attendance events at `school/agenda`. The web route is `/agenda`;
Android and macOS present this area as “Events & Substitutions”.

## Web application

The web application is provider-neutral and uses `DashboardApp` and
`LoginForm`. Its screens include login and two-factor authentication,
dashboard, messages, compose/reply, homework and its trash, timetable,
grades, settings, devices, API token management, and events/substitutions.

- The English catalog is the source of UI strings:
  `apps/web/messages/en.json`. Use `t()` rather than hardcoding user-visible
  text.
- The session proxy under `apps/web/src/app/api/` forwards requests using
  `API_SERVER_URL`.
- The visual design is defined in `apps/web/src/app/uber.css`.

## Android application

The Android application uses Kotlin, Jetpack Compose, and MVVM organized by
feature. Keep networking behind the shared Retrofit `ApiService`; bearer
authentication is added centrally, and tokens are stored through the
DataStore-backed `TokenStore`.

The established stack includes Compose BOM 2024.06.00, Navigation Compose
2.7.7, DataStore 1.1.1, Retrofit 2.11.0, OkHttp 4.12.0, and
kotlinx-serialization 1.7.3. The minimum SDK is 26; compile/target SDK is 34,
and the JVM target is 17.

The shared UI and navigation foundation includes `ui/theme/`,
`ui/common/RedesignUi.kt`, `Routes.kt`, `BottomBar.kt`, `NavGraph.kt`, and
the `data/` interfaces. Build new features on these established interfaces.
When changing `NavGraph`, limit changes to the feature's own destinations.
Keep DTO parsing tolerant of unknown fields.

Implemented areas include onboarding and login with two-factor
authentication; homework; messages and threads; day/week timetable; grades;
settings and devices; dashboard; and school events and substitutions. The
default emulator API URL is `http://10.0.2.2:3000/api/v1/` and can be changed
in login or settings.

Use the Gradle 8.7 distribution to build and run offline unit tests from
`android/`:

```sh
<GRADLE-DIST>/gradle-8.7/bin/gradle :app:assembleDebug :app:testDebugUnitTest
```

Tests use a fake `ApiService`.

## macOS application

The macOS application uses SwiftUI, Swift 5 language mode, macOS 14+, and
system frameworks. Its design follows the web application, including the
pill navigation and accent colors; light/dark appearance follows the system.
The app uses an observable store, feature-level views/view models/repositories,
one `APIClient`, and one `TokenStore`.

Implemented areas include authentication, settings and devices, messages,
homework, grades, timetable, dashboard, and school events/substitutions.
DTOs should remain aligned with `@eduflow/contracts`, and user-facing error
text should follow the backend catalog.

The local API normally runs on `http://127.0.0.1:3000`. Build and test with:

```sh
xcodebuild -project "mac/EduFlow Mac.xcodeproj" \
  -scheme "EduFlow Mac" -destination 'platform=macOS' test
```

Tests use route-specific URL stubs and do not require network access or real
credentials.

## iOS application

The existing iOS client is built with SwiftUI and system frameworks and is
currently on hold. Do not undertake new iOS work unless explicitly asked.
Its default API URL is `http://127.0.0.1:3000/api/v1/`. If a requested change
requires adding a source file, register it in
`ios/EduFlow iOS.xcodeproj/project.pbxproj` as required by the project.

## Shared branding and design

`static/icons/icon.png` is the source application icon. Platform icons and
headers should use assets derived from this source. Android and iOS app
screens follow the provided native app-screen design assets. macOS follows
the web design in `apps/web/src/app/uber.css`.

## Localization and language

- English is the source language and fallback for all outward-facing
  content, including documentation, code comments, identifiers, scripts,
  commit messages, branches, pull requests, issues, release notes, and
  workflow names and messages.
- Translate user-visible strings using the platform's source catalog; do
  not hardcode UI text.
- Web: `apps/web/messages/en.json`, accessed through `t()`.
- Backend: `apps/api/src/messages/en.json`, accessed through `t()`.
- Android: `values/strings.xml`, accessed through `stringResource`.
- macOS: `Localizable.xcstrings`; use `NSLocalizedString` where needed for
  dynamic strings.
- Translation catalogs other than English are managed by Crowdin. Do not
  edit them manually.
- Keep API codes, status/type values, and routes stable and untranslated.
  Catalog conventions are documented in `crowdin.yml` and
  `migration/check-catalogs.py`.

## Development workflow

- Make focused, compatible changes and follow established patterns in the
  affected platform.
- Check the relevant build and tests after changing code. Tests must work
  offline with fake providers, fake clients, or URL stubs.
- For backend changes, run `npm test` and `npm run typecheck`. The API tests
  use the fake provider.
- For web changes, run `npm run typecheck` from the repository root and the
  applicable tests.
- Android unit tests are run with the Gradle command documented above.
- macOS tests are run with the `xcodebuild` command documented above.
- Work on a branch based on `main`. If another change is in progress in the
  same files, verify the current state before editing; never overwrite
  changes blindly.
- Commits and pushes, when explicitly requested, must use the GitHub account
  `ABOYrbx` and its GitHub noreply address, not a real name or local machine
  email.

## Out of scope

Do not add push notifications, file uploads from client applications,
multi-user support, or production deployment unless explicitly requested.
