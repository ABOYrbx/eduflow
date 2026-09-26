#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

for command in node npm curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Fehlt: %s ist nicht installiert oder nicht im PATH.\n' "$command" >&2
    exit 1
  fi
done

if [ ! -d node_modules ]; then
  printf 'Abhängigkeiten fehlen. Bitte zuerst „npm install“ ausführen.\n' >&2
  exit 1
fi

if [ ! -f apps/api/.env.local ] && [ ! -f apps/api/.env ] && [ -z "${DATABASE_URL:-}" ]; then
  printf 'Datenbankkonfiguration fehlt. Bitte zuerst ./install.sh ausführen.\n' >&2
  exit 1
fi

EDUFLOW_PROVIDER=fake PORT=8101 npm run dev:api &
API_PID=$!

stop_api() {
  trap - EXIT INT TERM
  kill "$API_PID" 2>/dev/null || true
  wait "$API_PID" 2>/dev/null || true
}
trap stop_api EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Warte auf API unter http://localhost:8101/api/v1/health …\n'
API_READY=0
ATTEMPT=0
while [ "$ATTEMPT" -lt 20 ]; do
  if curl --connect-timeout 1 --max-time 2 --fail --silent http://127.0.0.1:8101/api/v1/health >/dev/null 2>&1; then
    API_READY=1
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 1
done

if [ "$API_READY" -ne 1 ]; then
  printf 'API ist nicht gestartet. Prüfe PostgreSQL und die lokale API-Konfiguration.\n' >&2
  exit 1
fi

printf 'Starte Weboberfläche; Next.js wählt bei Bedarf einen freien Port …\n'
npm run dev:web
