# Development

Work on your own branch off `main`. Tests run offline (fake provider / fake clients / URL stubs) — never with real credentials.

## Checks (must stay green)

```sh
npm run typecheck   # all packages (contracts, api, web)
npm test            # API: Jest, offline with fake provider
cd android && <GRADLE-DIST>/gradle-8.7/bin/gradle :app:assembleDebug :app:testDebugUnitTest
cd mac && xcodebuild -project "EduFlow Mac.xcodeproj" -scheme "EduFlow Mac" -destination 'platform=macOS' test
```

## Conventions

- **Identity**: commits via the GitHub account only — no real names or local machine paths (`/Users/<name>/…`, hostnames) in commits or tracked files. Never commit build/output folders (`build/`, `.gradle/`, `DerivedData/`, `xcuserdata/`) or secrets (`.env*`, `.cache/`, DB/vault access).
- **Strings**: UI text lives in the platform source files so Crowdin can translate it — web → `apps/web/messages/de.json` via `t()`, backend → `apps/api/src/messages/de.json` via `t()`, Android → `values/strings.xml` via `stringResource`, macOS → `Localizable.xcstrings` (`NSLocalizedString` for dynamic spots). English is source and fallback everywhere; German is one catalog among many. `code` vocabulary, status/type values and routes stay stable and are never translated.
- **Backend**: additive routes are fine as long as existing responses and DTOs stay compatible. New backend dependencies need justification.
- **Publishing**: docs in `docs/` sync to GitBook via Git Sync (`gitbook-docs.yaml`, space `eduflow`).
