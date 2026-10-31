#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEMO=false
NO_BUILD=false
STOP=false

usage() {
  cat <<'EOF'
Usage: ./install-docker.sh [--demo] [--no-build]
       ./install-docker.sh --stop

Options:
  --demo      Use the fake provider (login: demo / demo).
  --no-build  Skip image build; use existing images.
  --stop      Stop the Docker Compose services.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --demo) DEMO=true ;;
    --no-build) NO_BUILD=true ;;
    --stop) STOP=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is not installed or not in PATH.\n' >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  printf 'Docker Compose is not available (docker compose).\n' >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is not installed or not in PATH.\n' >&2
  exit 1
fi

if [[ "$STOP" == true ]]; then
  docker compose down
  printf 'EduFlow Docker services stopped.\n'
  exit 0
fi

set_env_var() {
  local key="$1" value="$2" file="$3"
  if grep -qE "^${key}=" "$file"; then
    awk -v k="$key" -v v="$value" 'BEGIN { FS = OFS = "=" } $1 == k { $0 = k "=" v } { print }' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

if [[ ! -f .env ]]; then
  if [[ ! -f .env.example ]]; then
    printf '.env.example is missing.\n' >&2
    exit 1
  fi
  cp .env.example .env
  chmod 600 .env 2>/dev/null || true

  if command -v openssl >/dev/null 2>&1; then
    jwt_secret="$(openssl rand -base64 32)"
    credential_key="$(openssl rand -hex 32)"
    set_env_var "JWT_ACCESS_SECRET" "$jwt_secret" ".env"
    set_env_var "CREDENTIAL_ENCRYPTION_KEY" "$credential_key" ".env"
  else
    printf 'openssl not found; keeping placeholder secrets from .env.example.\n'
  fi
fi

if [[ "$DEMO" == true ]]; then
  set_env_var "DEMO" "true" ".env"
  set_env_var "EDUFLOW_PROVIDER" "fake" ".env"
fi

API_PORT="${API_PORT:-}"
if [[ -z "$API_PORT" && -f .env ]]; then
  API_PORT="$(grep -E '^API_PORT=' .env | tail -n 1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
fi
API_PORT="${API_PORT:-3000}"

if [[ "$DEMO" == true ]]; then
  export DEMO=true
  export EDUFLOW_PROVIDER=fake
fi

if [[ "$NO_BUILD" == true ]]; then
  docker compose up -d
else
  docker compose up -d --build
fi

HEALTH_URL="http://127.0.0.1:${API_PORT}/api/v1/health"
READY=0
for ((i = 0; i < 120; i++)); do
  if curl --connect-timeout 1 --max-time 2 --fail --silent "$HEALTH_URL" 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    READY=1
    break
  fi
  sleep 1
done

if [[ "$READY" -ne 1 ]]; then
  printf 'EduFlow backend did not become healthy within 120 seconds.\n' >&2
  printf 'Check logs with: docker compose logs\n' >&2
  exit 1
fi

printf '\nEduFlow backend is running.\n'
printf 'API:    http://127.0.0.1:%s/api/v1\n' "$API_PORT"
printf 'Health: %s\n' "$HEALTH_URL"
if [[ "$DEMO" == true ]]; then
  printf 'Demo login: demo / demo (2FA demo: demo-2fa / demo, code 123456)\n'
else
  printf 'Sign in with your EduPage account.\n'
fi
printf 'Web UI is not containerized; run ./run.sh for the web interface (default http://localhost:8000/).\n'
