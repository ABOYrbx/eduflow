# Installation

## Prerequisites

| Requirement | Details |
|---|---|
| OS | macOS with Homebrew **or** Debian/Ubuntu Linux with `apt-get` + `sudo` for automatic Postgres setup. Other systems: provide your own Postgres. |
| Node.js | `20.9+` plus `npm` (`node -v`) |
| Tools | `node`, `npm`, `curl`, `nohup` in `PATH` |
| Postgres | `16` (auto-installed) or an existing server (default `127.0.0.1:5432`) |
| Ports | Real: API `3000`, Web `8000`. Demo: API `3100`, Web `8101`. Never auto-switched — `run.sh` aborts if occupied. Override with `API_PORT=… WEB_PORT=…`. |
| Native builds (optional) | Android SDK + Gradle `8.7`, or Xcode `16+` on macOS `14+` |
| Docker (optional) | Docker with the Compose plugin (`docker compose`) for the Docker backend quick start. |

## Steps

```sh
# 1. Clone
git clone https://github.com/ABOYrbx/eduflow.git
cd eduflow

# 2. Setup assistant (interactive TTY required).
#    Asks about Postgres, generates apps/api/.env.local (0600),
#    runs npm install + Prisma migrate.
./install.sh
```

What `install.sh` does:

1. Refuses to run if `apps/api/.env.local` already exists (delete it manually to redo setup — it never reads or overwrites secrets).
2. Asks whether Postgres is already available.
   - **No** → installs `postgresql@16` (Homebrew) or `postgresql` (`apt`), prompts for DB name/user (defaults `eduflow_dev` / `eduflow`), generates a password, creates role + database.
   - **Yes** → prompts for host, port, DB name, user and hidden password. The database must already exist.
3. Prompts for a JWT secret (empty = generate, min 32 chars) and a 64-hex credential key (empty = generate).
4. Writes `apps/api/.env.local` with `0600` (`DATABASE_URL`, `PORT="3000"`, `JWT_ACCESS_SECRET`, `CREDENTIAL_ENCRYPTION_KEY`, `EDUFLOW_PROVIDER="edupage"`), generates the Prisma client and deploys migrations.

Config files, logs and PIDs live outside git: `apps/api/.env.local`, `.cache/eduflow-{api,web}.{log,pid}` — never commit them.

## Docker backend (recommended for quick start)

For a quick start without a local PostgreSQL/NestJS setup, use the Docker
backend. It runs the API and PostgreSQL in containers; the web UI is still run
separately (see `./run.sh` or `npm run dev:web`).

```sh
# Real mode: generates .env, builds images, starts db + api, waits for health.
./install-docker.sh

# Demo mode (fake provider, login: demo / demo):
./install-docker.sh --demo

# Stop the services:
./install-docker.sh --stop

# Or build and start directly with Compose:
docker compose up -d --build
```

`install-docker.sh` also accepts `--no-build` to skip the image build and use
existing images.

What `install-docker.sh` does:

1. Requires `docker`, `docker compose`, and `curl` in `PATH`.
2. If `.env` is missing, copies `.env.example` to `.env` (mode `0600`) and
   generates `JWT_ACCESS_SECRET` and `CREDENTIAL_ENCRYPTION_KEY` with
   `openssl` when available; otherwise keeps the placeholder values from
   `.env.example`.
3. With `--demo`, sets `DEMO=true` and `EDUFLOW_PROVIDER=fake`.
4. Builds (unless `--no-build`) and starts the Compose services, then polls
   `http://127.0.0.1:<API_PORT>/api/v1/health` for up to 120 seconds until
   it reports `"status":"ok"`.

`.env` generation and secrets:

- `.env` is created only if it does not already exist; existing files are
  never overwritten.
- Secrets (`JWT_ACCESS_SECRET`, `CREDENTIAL_ENCRYPTION_KEY`) are generated
  once and stored in `.env`. Set strong values before real use; never commit
  `.env`.
- Database credentials default to `eduflow` / `eduflow` / `eduflow_dev` and
  can be adjusted in `.env`.

Ports and health check:

- API port defaults to `3000` (`API_PORT`), Postgres to `5432`
  (`POSTGRES_PORT`); override via `.env` or environment variables.
- Health check: `GET http://127.0.0.1:<API_PORT>/api/v1/health` returns
  `{"status":"ok",...}`.
- The web UI is not containerized; run it with `./run.sh` or
  `npm run dev:web` (default `http://localhost:8000`).

The native `./install.sh` remains available for a local PostgreSQL + NestJS
setup (see above).
