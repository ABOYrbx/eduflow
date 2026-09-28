#!/usr/bin/env sh
# EduFlow starten – echte Version (NestJS-API mit EduPage-Provider + Next.js-Web).
#
# Verwendung:
#   ./run.sh                echte Version: API http://0.0.0.0:3000, Web http://0.0.0.0:8000
#   ./run.sh --demo         Demo-Version (Fake-Provider): API :3100, Web :8101, Login demo / demo
#   ./run.sh --background   im Hintergrund laufen lassen (läuft weiter, auch wenn das Terminal zugeht)
#   ./stop.sh               Hintergrunddienste wieder stoppen
#   ./run.sh --help         diese Hilfe
#
# Eigene Ports/Hosts (werden geprüft, nie still gewechselt):
#   API_PORT=3000 WEB_PORT=8000 API_HOST=0.0.0.0 WEB_HOST=0.0.0.0 ./run.sh
# Logs/PIDs im Hintergrundmodus: .cache/eduflow-{api,web}.{log,pid}
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

MODE=real
BG=0
for arg in "$@"; do
  case "$arg" in
    --demo) MODE=demo ;;
    --background|-b) BG=1 ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      printf 'Unbekannte Option: %s\nVerwendung: ./run.sh [--demo] [--background]\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ "$MODE" = demo ]; then
  PROVIDER=fake
  API_PORT=${API_PORT:-3100}
  WEB_PORT=${WEB_PORT:-8101}
  # Own build output so demo web runs next to the real web server:
  # Next.js refuses a second `next dev` in one directory (dev lockfile).
  WEB_DIST_DIR=${NEXT_DIST_DIR:-.next-demo}
  LOGIN_HINT='Demo-Login: demo / demo (2FA-Demo: demo-2fa / demo, Code 123456)'
else
  PROVIDER=edupage
  API_PORT=${API_PORT:-3000}
  WEB_PORT=${WEB_PORT:-8000}
  WEB_DIST_DIR=${NEXT_DIST_DIR:-.next}
  LOGIN_HINT='Anmelden mit deinem EduPage-Account (Subdomain + Benutzername + Passwort)'
fi
# Bindung an alle Interfaces (LAN/Handy erreichbar); per ENV einschränkbar.
API_HOST=${API_HOST:-0.0.0.0}
WEB_HOST=${WEB_HOST:-0.0.0.0}
# PID-/Log-Dateien für den Hintergrundmodus (liegt in .cache/, wird nie committet).
RUN_DIR="$ROOT_DIR/.cache"
API_PIDFILE="$RUN_DIR/eduflow-api.pid"
WEB_PIDFILE="$RUN_DIR/eduflow-web.pid"
API_LOG="$RUN_DIR/eduflow-api.log"
WEB_LOG="$RUN_DIR/eduflow-web.log"

require_not_running() {
  if [ -f "$1" ]; then
    oldpid=$(cat "$1" 2>/dev/null || true)
    oldpid=${oldpid%% *}
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      printf '%s läuft bereits (PID %s). Erst ./stop.sh ausführen.\n' "$2" "$oldpid" >&2
      exit 1
    fi
    rm -f "$1"
  fi
}
# Eigene Session => Terminal-Schließen (SIGHUP) erreicht die Dienste nicht.
# macOS kennt kein setsid, dort bleibt es bei nohup.
if command -v setsid >/dev/null 2>&1; then
  BG_LAUNCH="setsid"
else
  BG_LAUNCH=""
fi

for command in node npm curl nohup; do
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

if [ "$BG" = 1 ]; then
  mkdir -p "$RUN_DIR"
  require_not_running "$API_PIDFILE" "API"
  require_not_running "$WEB_PIDFILE" "Web"
  printf 'Starte API (%s-Modus) im Hintergrund … (Log: %s)\n' "$PROVIDER" "$API_LOG"
  # shellcheck disable=SC2086 # BG_LAUNCH ist absichtlich unquoted (leer oder setsid).
  EDUFLOW_PROVIDER="$PROVIDER" API_HOST="$API_HOST" PORT="$API_PORT" $BG_LAUNCH nohup npm run dev:api >>"$API_LOG" 2>&1 < /dev/null &
  API_PID=$!
  printf '%s %s' "$API_PID" "$API_PORT" > "$API_PIDFILE"
else
  EDUFLOW_PROVIDER="$PROVIDER" API_HOST="$API_HOST" PORT="$API_PORT" npm run dev:api &
  API_PID=$!

  stop_api() {
    trap - EXIT INT TERM
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  }
  trap stop_api EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

printf 'Warte auf API (%s-Modus) unter http://127.0.0.1:%s/api/v1/health …\n' "$PROVIDER" "$API_PORT"
API_READY=0
ATTEMPT=0
while [ "$ATTEMPT" -lt 90 ]; do
  # Inhalt prüfen, nicht nur HTTP 200: Auf dem Port könnte ein fremder Dienst
  # antworten (z. B. Docker-Publish auf demselben Host-Port).
  if curl --connect-timeout 1 --max-time 2 --fail --silent "http://127.0.0.1:$API_PORT/api/v1/health" 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    API_READY=1
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 1
done

if [ "$API_READY" -ne 1 ]; then
  printf 'API ist nicht gestartet. Prüfe die Ausgabe oben sowie PostgreSQL und apps/api/.env.local.\n' >&2
  if [ "$BG" = 1 ]; then
    printf 'Räume Hintergrund-API wieder auf …\n' >&2
    kill "$API_PID" 2>/dev/null || true
    rm -f "$API_PIDFILE"
  fi
  exit 1
fi

printf 'API bereit: http://%s:%s/api/v1\n' "$API_HOST" "$API_PORT"
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$LAN_IP" ]; then
  printf 'Handy im gleichen WLAN: API http://%s:%s/api/v1 (in der App als Server eintragen), Web http://%s:%s/\n' "$LAN_IP" "$API_PORT" "$LAN_IP" "$WEB_PORT"
fi
if [ "$BG" = 1 ]; then
  printf 'Starte Weboberfläche im Hintergrund auf %s:%s … (Log: %s)\n' "$WEB_HOST" "$WEB_PORT" "$WEB_LOG"
  # Next direkt aufrufen (kein verschachteltes `npm run --workspace`, das die
  # --hostname/--port-Flags als Workspace-Verzeichnis fehlinterpretiert).
  # shellcheck disable=SC2086 # BG_LAUNCH ist absichtlich unquoted (leer oder setsid).
  API_SERVER_URL="http://127.0.0.1:$API_PORT" PORT="$WEB_PORT" $BG_LAUNCH nohup "$ROOT_DIR/node_modules/.bin/next" dev "$ROOT_DIR/apps/web" --hostname "$WEB_HOST" --port "$WEB_PORT" >>"$WEB_LOG" 2>&1 < /dev/null &
  WEB_PID=$!
  printf '%s %s' "$WEB_PID" "$WEB_PORT" > "$WEB_PIDFILE"
  printf 'Warte auf Web unter http://127.0.0.1:%s/ …\n' "$WEB_PORT"
  WEB_READY=0
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 60 ]; do
    if ! port_free "$WEB_PORT"; then
      WEB_READY=1
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
  done
  if [ "$WEB_READY" -ne 1 ]; then
    printf 'Web ist nicht gestartet. Siehe %s. Räume Hintergrunddienste wieder auf …\n' "$WEB_LOG" >&2
    kill "$WEB_PID" 2>/dev/null || true
    rm -f "$WEB_PIDFILE"
    kill "$API_PID" 2>/dev/null || true
    rm -f "$API_PIDFILE"
    exit 1
  fi
  printf 'Läuft im Hintergrund (bleibt auch nach Schließen des Terminals an):\n'
  printf '  Web: http://localhost:%s/ (%s)\n' "$WEB_PORT" "$LOGIN_HINT"
  printf '  Logs: %s, %s\n' "$API_LOG" "$WEB_LOG"
  printf 'Stoppen mit: ./stop.sh\n'
  exit 0
fi
printf 'Starte Weboberfläche auf %s:%s …\n' "$WEB_HOST" "$WEB_PORT"
printf 'Web: http://localhost:%s/ (%s)\n' "$WEB_PORT" "$LOGIN_HINT"
# Next direkt aufrufen (kein verschachteltes `npm run --workspace`, das die
# --hostname/--port-Flags als Workspace-Verzeichnis fehlinterpretiert).
API_SERVER_URL="http://127.0.0.1:$API_PORT" PORT="$WEB_PORT" NEXT_DIST_DIR="$WEB_DIST_DIR" "$ROOT_DIR/node_modules/.bin/next" dev "$ROOT_DIR/apps/web" --hostname "$WEB_HOST" --port "$WEB_PORT"
