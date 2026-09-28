#!/usr/bin/env sh
# EduFlow-Hintergrunddienste stoppen (Gegenstück zu ./run.sh --background).
#
# Verwendung:
#   ./stop.sh
#
# Stoppt anhand der PID-Dateien in .cache/ (ganzer Prozessbaum) und räumt
# danach ggf. verwaiste Listener auf den zugehörigen Ports weg.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

RUN_DIR="$ROOT_DIR/.cache"
SWEEP_PORTS=""

kill_tree() {
  sig=$1
  target=$2
  if [ "$target" = "$$" ]; then
    return 0
  fi
  for child in $(ps -e -o pid= -o ppid= 2>/dev/null | awk -v p="$target" '$2 == p { print $1 }'); do
    kill_tree "$sig" "$child"
  done
  kill "-$sig" "$target" 2>/dev/null || true
}

still_alive() {
  pid=$1
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

pids_listening_on() {
  port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | sed -n "s/.*:${port}[^0-9].*pid=\([0-9][0-9]*\).*/\1/p" | sort -u
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null
    return 0
  fi
  if [ -r /proc/net/tcp ]; then
    hexport=$(printf '%04X' "$port" 2>/dev/null || true)
    inodes=$(awk -v hp="$hexport" 'NR > 1 && $4 == "0A" { split($2, a, ":"); if (a[2] == hp) print $10 }' /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u)
    if [ -n "$inodes" ]; then
      for procdir in /proc/[0-9]*; do
        pid=${procdir#/proc/}
        for fd in "$procdir"/fd/*; do
          link=$(readlink "$fd" 2>/dev/null || true)
          case "$link" in
            socket:\[*)
              ino=${link#socket:[}
              ino=${ino%]}
              case " $inodes " in
                *" $ino "*)
                  printf '%s\n' "$pid"
                  break
                  ;;
              esac
              ;;
          esac
        done
      done | sort -u
    fi
    return 0
  fi
  return 0
}

sweep_port() {
  port=$1
  listeners=$(pids_listening_on "$port" || true)
  if [ -z "$listeners" ]; then
    return 0
  fi
  printf 'Port %s ist noch belegt, räume verwaiste Prozesse auf (PIDs: %s) …\n' "$port" "$(printf '%s' "$listeners" | tr '\n' ' ')"
  for pid in $listeners; do
    kill_tree TERM "$pid"
  done
  i=0
  while [ "$i" -lt 10 ]; do
    listeners=$(pids_listening_on "$port" || true)
    if [ -z "$listeners" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  listeners=$(pids_listening_on "$port" || true)
  if [ -n "$listeners" ]; then
    for pid in $listeners; do
      kill_tree KILL "$pid"
    done
    sleep 1
  fi
  listeners=$(pids_listening_on "$port" || true)
  if [ -n "$listeners" ]; then
    printf 'Port %s bleibt belegt (PIDs: %s) – bitte manuell prüfen.\n' "$port" "$(printf '%s' "$listeners" | tr '\n' ' ')" >&2
  else
    printf 'Port %s ist frei.\n' "$port"
  fi
}

stop_one() {
  name=$1
  pidfile=$2
  if [ ! -f "$pidfile" ]; then
    printf '%s: nicht gestartet (keine PID-Datei).\n' "$name"
    return 0
  fi
  entry=$(cat "$pidfile" 2>/dev/null || true)
  pid=${entry%% *}
  case "$entry" in
    *' '*) rest=${entry#* } ;;
    *) rest="" ;;
  esac
  case "$rest" in
    ''|*[!0-9]*)
      port=""
      ;;
    *)
      port=$rest
      ;;
  esac
  rm -f "$pidfile"
  case "$pid" in
    ''|*[!0-9]*)
      printf '%s: ungültige PID-Datei, aufgeräumt.\n' "$name"
      ;;
    *)
      if ! kill -0 "$pid" 2>/dev/null; then
        printf '%s: Hauptprozess bereits weg (PID %s).\n' "$name" "$pid"
      else
        printf '%s wird gestoppt (PID %s) …\n' "$name" "$pid"
        kill_tree TERM "$pid"
        if still_alive "$pid"; then
          printf '%s reagiert nicht, erzwinge Abbruch …\n' "$name"
          kill_tree KILL "$pid"
          sleep 1
        fi
        printf '%s gestoppt.\n' "$name"
      fi
      ;;
  esac
  if [ -n "$port" ]; then
    case " $SWEEP_PORTS " in
      *" $port "*) ;;
      *) SWEEP_PORTS="$SWEEP_PORTS $port" ;;
    esac
  fi
}

stop_one "API" "$RUN_DIR/eduflow-api.pid"
stop_one "Web" "$RUN_DIR/eduflow-web.pid"
for port in $SWEEP_PORTS; do
  sweep_port "$port"
done
