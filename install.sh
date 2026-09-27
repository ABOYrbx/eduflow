#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  printf '\033[38;2;20;102;251m'
fi
cat <<'EDUFLOW_ICON'


                    ██████
              ████████████████
          ██████████████████████████
      ██████████████████████████████████
    ██████████████████████████████████████
        ████████████████████████████████
            ████              ████    ██
                ██████████████        ██
            ████████████████████      ████
          ████████████████████████    ████
          ██████            ████████  ██
        ██████            ██████████
        ████        ████████████████
        ██      ████████████████
            ██████████████
          ████████████
          ████████            ████████
          ████████████████████████████
            ████████████████████████
              ██████████████████
                    ██████
EDUFLOW_ICON
printf '\n'
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  printf '\033[1;38;2;20;102;251m'
fi
cat <<'EDUFLOW_WORDMARK'
██████      ██  ██  ██  ██████  ██      ██    ██  ██
██          ██  ██  ██  ██      ██    ██  ██  ██  ██
██      ██████  ██  ██  ██      ██    ██  ██  ██  ██
████    ██  ██  ██  ██  ████    ██    ██  ██  ██████
██      ██  ██  ██  ██  ██      ██    ██  ██  ██████
██      ██  ██  ██  ██  ██      ██    ██  ██  ██  ██
██████  ██████  ██████  ██      ████    ██    ██  ██
EDUFLOW_WORDMARK
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  printf '\033[0m'
fi
printf '\n                  Installer\n\n'

DEBUG=0
if (( $# > 1 )); then
  printf 'Verwendung: ./install.sh [-debug]\n' >&2
  exit 2
fi
case "${1:-}" in
  '') ;;
  -debug|--debug) DEBUG=1 ;;
  *)
    printf 'Unbekannte Option: %s\nVerwendung: ./install.sh [-debug]\n' "$1" >&2
    exit 2
    ;;
esac

SYSTEM_KIND="$(uname -s)"
SYSTEM_ARCH="$(uname -m)"
case "$SYSTEM_KIND" in
  Darwin) SYSTEM_LABEL="macOS ($SYSTEM_ARCH)" ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      SYSTEM_LABEL="Linux mit apt-get ($SYSTEM_ARCH)"
    else
      SYSTEM_LABEL="Linux ohne apt-get ($SYSTEM_ARCH)"
    fi
    ;;
  *) SYSTEM_LABEL="$SYSTEM_KIND ($SYSTEM_ARCH)" ;;
esac
printf 'System erkannt: %s\n' "$SYSTEM_LABEL"
if (( ! DEBUG )); then
  printf 'Für Details: ./install.sh -debug\n'
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'Installer: %s\n' "$1" >&2
  exit 1
}

run_step() {
  local label="$1" failure_message="$2"
  shift 2

  if (( DEBUG )); then
    printf '\n%s\n' "$label"
    "$@" || fail "$failure_message"
  else
    printf '%s … ' "$label"
    if "$@" >/dev/null 2>&1; then
      printf 'fertig\n'
    else
      printf 'fehlgeschlagen\n'
      fail "$failure_message (für Details ./install.sh -debug verwenden)"
    fi
  fi
}

provision_local_postgres() {
  printf '%s\0' "$platform" "$DB_USER" "$DB_NAME" "$DB_PASSWORD" | node migration/provision-postgres.cjs
}

write_local_config() {
  printf '%s\0' "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$JWT_SECRET" "$CREDENTIAL_KEY" | node migration/write-api-config.cjs
}

start_macos_postgres() {
  local data_dir pg_ctl attempt

  data_dir="$(brew --prefix)/var/postgresql@16"
  pg_ctl="$(brew --prefix postgresql@16)/bin/pg_ctl"
  [[ -x "$pg_ctl" ]] || {
    printf 'Das Homebrew-Programm pg_ctl wurde nicht gefunden.\n' >&2
    return 1
  }
  [[ -s "$data_dir/PG_VERSION" ]] || {
    printf 'Das PostgreSQL-Datenverzeichnis wurde nicht initialisiert.\n' >&2
    return 1
  }

  # Ein offener Port reicht nicht: dort könnte ein anderer PostgreSQL-Dienst
  # laufen. Für den lokalen Installationsweg muss es genau dieser Brew-Cluster sein.
  if "$pg_ctl" -D "$data_dir" status >/dev/null 2>&1; then
    if pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1; then
      printf 'Der Homebrew-PostgreSQL-Dienst läuft und antwortet auf %s:%s.\n' "$DB_HOST" "$DB_PORT"
      return 0
    fi
    printf 'Der Homebrew-PostgreSQL-Dienst läuft, antwortet aber nicht auf %s:%s.\n' "$DB_HOST" "$DB_PORT" >&2
    return 1
  fi

  if pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1; then
    printf 'Port %s wird bereits von einem anderen PostgreSQL-Dienst belegt.\n' "$DB_PORT" >&2
    printf 'Starte den Installer erneut und wähle „j“, um dessen Verbindungsdaten einzugeben, oder beende den anderen Dienst.\n' >&2
    return 1
  fi

  if brew services start postgresql@16; then
    for ((attempt = 1; attempt <= 10; attempt++)); do
      if "$pg_ctl" -D "$data_dir" status >/dev/null 2>&1; then
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1; then
          return 0
        fi
        printf 'Der Homebrew-PostgreSQL-Dienst läuft, ist aber auf %s:%s nicht erreichbar.\n' "$DB_HOST" "$DB_PORT" >&2
        return 1
      fi
      sleep 1
    done
  fi

  printf 'Homebrew konnte den LaunchAgent nicht starten; versuche pg_ctl direkt.\n' >&2
  if "$pg_ctl" -D "$data_dir" -l /dev/stderr -w -t 30 start; then
    if "$pg_ctl" -D "$data_dir" status >/dev/null 2>&1 && pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1; then
      return 0
    fi
    printf 'Der Homebrew-PostgreSQL-Dienst wurde gestartet, antwortet aber nicht auf %s:%s.\n' "$DB_HOST" "$DB_PORT" >&2
    return 1
  fi

  if pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1; then
    printf 'Port %s wird inzwischen von einem anderen PostgreSQL-Dienst belegt. Wähle beim Neustart „j“ und gib dessen Verbindungsdaten ein.\n' "$DB_PORT" >&2
  fi
  return 1
}

for command in node npm; do
  command -v "$command" >/dev/null 2>&1 || fail "$command fehlt. Bitte Node.js 20.9+ und npm installieren."
done

if [[ ! -t 0 || ! -t 1 ]]; then
  fail 'Bitte direkt in einem interaktiven Terminal starten: ./install.sh'
fi

node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && minor >= 9) ? 0 : 1)' \
  || fail 'Node.js 20.9 oder neuer wird benötigt.'

CONFIG_FILE="$ROOT_DIR/apps/api/.env.local"
if [[ -e "$CONFIG_FILE" || -L "$CONFIG_FILE" ]]; then
  fail 'apps/api/.env.local existiert bereits.'
fi

install_local_postgres() {
  local platform pg_bin attempt

  DB_HOST=127.0.0.1
  DB_PORT=5432
  case "$SYSTEM_KIND" in
    Darwin)
      command -v brew >/dev/null 2>&1 || fail 'Für die automatische PostgreSQL-Installation auf macOS wird Homebrew benötigt.'
      if ! brew list --versions postgresql@16 >/dev/null 2>&1; then
        run_step 'Lade PostgreSQL 16 herunter und installiere es über Homebrew' \
          'PostgreSQL konnte über Homebrew nicht installiert werden.' brew install postgresql@16
      fi
      pg_bin="$(brew --prefix postgresql@16)/bin"
      [[ -x "$pg_bin/psql" ]] || fail 'Die PostgreSQL-Programme wurden nicht gefunden.'
      PATH="$pg_bin:$PATH"
      export PATH
      command -v pg_isready >/dev/null 2>&1 || fail 'Das PostgreSQL-Prüfprogramm pg_isready fehlt.'
      run_step 'Starte PostgreSQL' \
        'PostgreSQL konnte weder als Homebrew-Dienst noch direkt gestartet werden.' start_macos_postgres
      platform=macos
      ;;
    Linux)
      command -v apt-get >/dev/null 2>&1 || fail 'Automatische Installation wird derzeit unter Debian/Ubuntu (apt-get) unterstützt.'
      command -v sudo >/dev/null 2>&1 || fail 'Für die Installation unter Debian/Ubuntu wird sudo benötigt.'
      run_step 'Lade Paketlisten herunter' \
        'Die Paketlisten konnten nicht aktualisiert werden.' sudo apt-get update
      run_step 'Lade PostgreSQL herunter und installiere es' \
        'PostgreSQL konnte über apt nicht installiert werden.' sudo apt-get install -y postgresql postgresql-client
      if command -v systemctl >/dev/null 2>&1; then
        run_step 'Aktiviere und starte den PostgreSQL-Dienst' \
          'Der PostgreSQL-Dienst konnte nicht gestartet werden.' sudo systemctl enable --now postgresql
      elif command -v service >/dev/null 2>&1; then
        run_step 'Starte den PostgreSQL-Dienst' \
          'Der PostgreSQL-Dienst konnte nicht gestartet werden.' sudo service postgresql start
      else
        fail 'Der PostgreSQL-Dienst konnte nicht gestartet werden.'
      fi
      platform=linux
      ;;
    *)
      fail 'Automatische PostgreSQL-Installation wird auf macOS sowie Debian/Ubuntu unterstützt.'
      ;;
  esac

  read -r -p 'Name der neuen Datenbank [eduflow_dev]: ' DB_NAME
  DB_NAME="${DB_NAME:-eduflow_dev}"
  read -r -p 'Name des neuen Datenbankbenutzers [eduflow]: ' DB_USER
  DB_USER="${DB_USER:-eduflow}"
  if [[ ! "$DB_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ || ! "$DB_USER" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]; then
    fail 'Datenbankname und Benutzer dürfen nur mit Buchstaben oder _ beginnen und danach Buchstaben, Zahlen oder _ enthalten (maximal 63 Zeichen).'
  fi
  DB_PASSWORD="$(node -e 'process.stdout.write(require("node:crypto").randomBytes(32).toString("base64url"))')"

  command -v pg_isready >/dev/null 2>&1 || fail 'Das PostgreSQL-Prüfprogramm pg_isready fehlt.'
  printf 'Prüfe den lokalen PostgreSQL-Dienst …\n'
  attempt=0
  until if (( DEBUG )); then
    pg_isready -h "$DB_HOST" -p "$DB_PORT"
  else
    pg_isready -h "$DB_HOST" -p "$DB_PORT" >/dev/null 2>&1
  fi; do
    attempt=$((attempt + 1))
    if [[ "$attempt" -ge 30 ]]; then
      fail 'PostgreSQL wurde installiert, ist auf Port 5432 aber nicht erreichbar.'
    fi
    sleep 1
  done

  if [[ "$platform" == linux ]]; then
    sudo -v || fail 'sudo-Berechtigung wurde nicht bestätigt.'
  fi
  run_step 'Lege lokale EduFlow-Datenbank und Benutzer an' \
    'Die lokale PostgreSQL-Datenbank konnte nicht eingerichtet werden.' provision_local_postgres
}

read -r -p 'Ist PostgreSQL bereits installiert/verfügbar? [j/N]: ' PG_INSTALLED
case "$PG_INSTALLED" in
  [jJyY]*)
    read -r -p 'PostgreSQL-Host [127.0.0.1]: ' DB_HOST
    DB_HOST="${DB_HOST:-127.0.0.1}"
    read -r -p 'PostgreSQL-Port [5432]: ' DB_PORT
    DB_PORT="${DB_PORT:-5432}"
    read -r -p 'Datenbankname [eduflow_dev]: ' DB_NAME
    DB_NAME="${DB_NAME:-eduflow_dev}"
    read -r -p 'Datenbankbenutzer [eduflow]: ' DB_USER
    DB_USER="${DB_USER:-eduflow}"
    read -r -s -p 'Datenbankpasswort: ' DB_PASSWORD
    printf '\n'
    ;;
  [nN]*|'')
    install_local_postgres
    ;;
  *)
    fail 'Bitte mit j/ja oder n/nein antworten.'
    ;;
esac

printf 'JWT-Zugriffsschlüssel (leer = sicher generieren): '
IFS= read -r -s JWT_SECRET
printf '\n'
printf 'Verschlüsselungsschlüssel, 64 Hex-Zeichen (leer = sicher generieren): '
IFS= read -r -s CREDENTIAL_KEY
printf '\n\n'

if [[ ! "$DB_PORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$DB_PORT < 1 || 10#$DB_PORT > 65535 )); then
  fail 'Der PostgreSQL-Port muss zwischen 1 und 65535 liegen.'
fi
if [[ -z "$DB_NAME" || -z "$DB_USER" ]]; then
  fail 'Datenbankname und Benutzer dürfen nicht leer sein.'
fi
if [[ -z "$DB_HOST" || "$DB_HOST" =~ [[:space:]/@?#] ]]; then
  fail 'Der PostgreSQL-Host ist ungültig.'
fi
if [[ -n "$JWT_SECRET" && ${#JWT_SECRET} -lt 32 ]]; then
  fail 'Der JWT-Schlüssel muss mindestens 32 Zeichen haben.'
fi
if [[ -n "$CREDENTIAL_KEY" && ! "$CREDENTIAL_KEY" =~ ^[[:xdigit:]]{64}$ ]]; then
  fail 'Der Verschlüsselungsschlüssel muss aus genau 64 Hex-Zeichen bestehen.'
fi

run_step 'Lade npm-Pakete herunter und installiere sie' \
  'Die npm-Abhängigkeiten konnten nicht installiert werden.' npm install

umask 077
run_step 'Schreibe lokale Konfiguration mit Dateirechten 600' \
  'Die lokale Konfiguration konnte nicht geschrieben werden.' write_local_config
unset DB_PASSWORD JWT_SECRET CREDENTIAL_KEY

run_step 'Erzeuge Prisma Client' \
  'Der Prisma Client konnte nicht erzeugt werden.' npm run db:generate
run_step 'Wende additive Datenbankmigrationen an' \
  'Die Datenbankmigrationen konnten nicht angewendet werden.' npm run db:deploy

printf '\nInstallation abgeschlossen. Start mit ./run.sh\n'
printf 'Weboberfläche: http://localhost:8000/ (Anmelden mit deinem EduPage-Account)\n'
printf 'Demo-Modus (ohne echten Account): ./run.sh --demo, Login demo / demo\n'
