#!/usr/bin/env sh
# EduFlow starten – echte Version (NestJS-API mit EduPage-Provider + Next.js-Web).
#
# Verwendung:
#   ./run.sh            echte Version: API http://127.0.0.1:3000, Web http://localhost:8000
#   ./run.sh --demo     Demo-Version (Fake-Provider): API :8101, Web :3100, Login demo / demo
#   ./run.sh --help     diese Hilfe
#
# Eigene Ports (werden geprüft, nie still gewechselt):
#   API_PORT=3000 WEB_PORT=8000 ./run.sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

MODE=real
for arg in "$@"; do
  case "$arg" in
    --demo) MODE=demo ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      printf 'Unbekannte Option: %s\nVerwendung: ./run.sh [--demo]\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ "$MODE" = demo ]; then
  PROVIDER=fake
  API_PORT=${API_PORT:-8101}
  WEB_PORT=${WEB_PORT:-3100}
  LOGIN_HINT='Demo-Login: demo / demo (2FA-Demo: demo-2fa / demo, Code 123456)'
else
  PROVIDER=edupage
  API_PORT=${API_PORT:-3000}
  WEB_PORT=${WEB_PORT:-8000}
  LOGIN_HINT='Anmelden mit deinem EduPage-Account (Subdomain + Benutzername + Passwort)'
fi

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

port_free() {
  node -e 'const net = require("net"); const tryConnect = (host) => new Promise((resolve) => { const socket = net.connect(Number(process.argv[1]), host); socket.once("connect", () => { socket.end(); resolve("used"); }); socket.once("error", () => resolve("free")); socket.setTimeout(1000, () => { socket.destroy(); resolve("free"); }); }); Promise.all([tryConnect("127.0.0.1"), tryConnect("::1")]).then((results) => process.exit(results.includes("used") ? 1 : 0));' "$1" 2>/dev/null
}

if ! port_free "$API_PORT"; then
  printf 'Port %s ist belegt. API_PORT auf einen freien Port setzen oder den anderen Dienst beenden.\n' "$API_PORT" >&2
  exit 1
fi
if ! port_free "$WEB_PORT"; then
  printf 'Port %s ist belegt. WEB_PORT auf einen freien Port setzen oder den anderen Dienst beenden.\n' "$WEB_PORT" >&2
  exit 1
fi

printf 'Prüfe Datenbankschema (idempotent) …\n'
if ! npm run db:deploy; then
  printf 'Datenbankmigration fehlgeschlagen. Läuft PostgreSQL und stimmen die Daten in apps/api/.env.local?\n' >&2
  exit 1
fi

EDUFLOW_PROVIDER="$PROVIDER" PORT="$API_PORT" npm run dev:api &
API_PID=$!

stop_api() {
  trap - EXIT INT TERM
  kill "$API_PID" 2>/dev/null || true
  wait "$API_PID" 2>/dev/null || true
}
trap stop_api EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Warte auf API (%s-Modus) unter http://127.0.0.1:%s/api/v1/health …\n' "$PROVIDER" "$API_PORT"
API_READY=0
ATTEMPT=0
while [ "$ATTEMPT" -lt 90 ]; do
  if curl --connect-timeout 1 --max-time 2 --fail --silent "http://127.0.0.1:$API_PORT/api/v1/health" >/dev/null 2>&1; then
    API_READY=1
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 1
done

if [ "$API_READY" -ne 1 ]; then
  printf 'API ist nicht gestartet. Prüfe die Ausgabe oben sowie PostgreSQL und apps/api/.env.local.\n' >&2
  exit 1
fi

printf 'API bereit: http://127.0.0.1:%s/api/v1\n' "$API_PORT"
printf 'Starte Weboberfläche auf Port %s …\n' "$WEB_PORT"
printf 'Web: http://localhost:%s/ (%s)\n' "$WEB_PORT" "$LOGIN_HINT"
API_SERVER_URL="http://127.0.0.1:$API_PORT" PORT="$WEB_PORT" npm run dev:web
