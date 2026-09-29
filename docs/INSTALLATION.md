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
