# Architecture

```
                ┌──────────────┐      Bearer :3000/:3100      ┌──────────────────┐
                │  Android /   │◄────────────────────────────►│                  │
                │  macOS apps  │     /api/v1 (JSON)           │   NestJS API     │
                └──────────────┘                              │  apps/api        │
                                                              │  edupage|fake   │
┌──────────────┐  same-origin /api/*   ┌──────────────────┐    │  providers       │
│   Browser    │◄─────────────────────►│   Next.js web    │───►│                  │
│              │                       │   apps/web :8000 │ API_SERVER_URL       │
└──────────────┘                       │  session proxy   │    │  Postgres        │
                                       └──────────────────┘    │  (tokens, prefs, │
                                                             │   caches)        │
                                                             └──────────────────┘
```

## Backend (`apps/api`, NestJS, TypeScript)

The standard backend, wire-compatible on `/api/v1`. Two providers behind `EDUFLOW_PROVIDER`:

- `edupage` — real: lives off the login session (tokens/2FA against EduPage), passwords sealed in a credential vault, Postgres caches per resource with TTLs.
- `fake` — demo: login `demo`/`demo` (2FA path `demo-2fa`/`demo`, code `123456`), static fixtures plus per-account DB state.

Auth is Bearer-only (30 days, DB-backed), except file downloads which also accept a `?dl=` short token (5 min, recommended) or legacy `?token=`. 2FA is two-step: `auth/login` → `2fa_required` + `pending_token` (TTL 10 min), `auth/2fa` swaps it for a full token. Rate limit: 20 hits / 10 min / IP → `429`.

Errors are always `{error, code}` with a canonical vocabulary (`VALIDATION`, `TOKEN_INVALID/EXPIRED`, `PENDING_INVALID/INVALID_CODE`, `BAD_CREDENTIALS`, `EDUPAGE_2FA`, `CAPTCHA_REQUIRED`, `NOT_FOUND`, `RATE_LIMITED`, `CONFIG_MISSING`, `UPSTREAM`). Lists are always `{items, total, limit, offset}` (`limit` 50, max 200). DTOs mirror the web dicts 1:1 (shared via `@eduflow/contracts`); existing routes and DTOs stay compatible.

Route reference: `GET /api/v1/openapi.json`, `GET /api/v1/health` (no auth).

## Web UI (`apps/web`, Next.js)

All pages render through one client component (`DashboardApp`) behind a server-side session gate. The browser never calls the API directly: same-origin Next routes forward with `API_SERVER_URL`, keep `eduflow_access`/`eduflow_refresh` httpOnly cookies, and retry once via `auth/refresh` on upstream `401`. English is source and fallback (`messages/en.json`); German and 25+ other catalogs ship alongside.

## Native clients

- **Android** (`android/`, Kotlin + Compose, Material3): single activity + `NavGraph`, bottom bar (Home, Homework, Messages, Timetable, More), MVVM per feature, one Retrofit `ApiService` + DataStore `TokenStore` with Bearer interceptor, tolerant DTOs.
- **macOS** (`mac/`, Swift 5 + SwiftUI, macOS 14+, system frameworks only): single entry + top pill nav (web design), MVVM per feature, one `APIClient` + file-based `TokenStore` (`0600`, deliberately no Keychain), string catalog for localization.

Both stub the API per route for offline tests and treat any `401` as “back to login”.

## Backend with Docker

The NestJS backend and its PostgreSQL database can be run with Docker Compose using the repository-root `compose.yml` and `Dockerfile`. The web app is not part of the compose stack and runs separately (see [Platforms](PLATFORMS.md)).

Start the backend stack:

```sh
docker compose up -d
```

Rebuild after code or dependency changes:

```sh
docker compose up -d --build
```

Force a clean rebuild:

```sh
docker compose build --no-cache
docker compose up -d
```

Demo mode (fake provider, login `demo` / `demo`) is enabled with `DEMO=true`. The entrypoint switches `EDUFLOW_PROVIDER` to `fake` automatically:

```sh
DEMO=true docker compose up -d
```

Or set it in an environment file (`.env` next to `compose.yml`):

```env
DEMO=true
```

Ports:

- API: host `${API_PORT:-3000}` → container `3000` (default `http://127.0.0.1:3000/api/v1`).
- PostgreSQL: internal only (container port `5432`, no host port by default).

Environment variables (from `compose.yml`, with defaults):

- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` (database credentials, default `eduflow` / `eduflow` / `eduflow_dev`).
- `API_PORT` (host port for the API, default `3000`).
- `JWT_ACCESS_SECRET` (access token signing secret; replace in any non-demo use).
- `CREDENTIAL_ENCRYPTION_KEY` (seals stored EduPage credentials).
- `DEMO` (`true`/`1` enables demo mode).
- `EDUFLOW_PROVIDER` (`edupage` or `fake`).
- `OPENWEATHER_KEY` (optional weather integration).
- `EDUFLOW_TRUST_PROXY`, `EDUFLOW_API_TOKEN_DAYS`.

Database migrations are applied automatically on startup by `docker/entrypoint.sh` (`prisma migrate deploy`). Persistent data lives in the `postgres_data` volume and survives `docker compose down`; use `docker compose down -v` to remove it. Health check: `GET /api/v1/health` (no auth).
