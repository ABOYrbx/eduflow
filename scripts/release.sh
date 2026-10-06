#!/usr/bin/env sh
# Startet den manuellen Release-Workflow. Ohne diesen Umweg entsteht kein
# Release: der Workflow hat bewusst keinen push-/tag-Trigger.
#
# Aufruf:
#   scripts/release.sh 0.1.0                      # beide Apps
#   scripts/release.sh 0.1.0 --android
#   scripts/release.sh 0.1.0 --macos
#   scripts/release.sh 0.1.0 --dry-run            # nur bauen, nichts veroeffentlichen
#   scripts/release.sh 0.1.0 --notes "Erste Version"
#   scripts/release.sh 0.1.0 --final              # ohne Pre-Release-Markierung
#
# Die Version muss mit VERSION, android/app/build.gradle.kts und dem
# macOS-Projekt uebereinstimmen – sonst bricht der Workflow ab.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PLATFORM=both
DRY_RUN=false
PRERELEASE=true
NOTES=""
VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --android) PLATFORM=android ;;
    --macos)   PLATFORM=macos ;;
    --both)    PLATFORM=both ;;
    --dry-run) DRY_RUN=true ;;
    --final)   PRERELEASE=false ;;
    --notes)
      shift
      [ $# -gt 0 ] || { echo "FEHLER: --notes braucht einen Text." >&2; exit 2; }
      NOTES="$1"
      ;;
    --notes=*)
      NOTES="${1#--notes=}"
      ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    -*)
      echo "Unbekannte Option: $1" >&2
      exit 2
      ;;
    *)
      [ -z "$VERSION" ] || { echo "FEHLER: nur eine Version angeben." >&2; exit 2; }
      VERSION="$1"
      ;;
  esac
  shift
done

[ -n "$VERSION" ] || {
  echo "FEHLER: Versionsnummer fehlt, z. B. scripts/release.sh 0.1.0" >&2
  exit 2
}

printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "FEHLER: Version '$VERSION' muss x.y.z sein (oh fuehrendes v)." >&2
  exit 2
}

command -v gh >/dev/null 2>&1 || {
  echo "FEHLER: GitHub CLI (gh) fehlt." >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "FEHLER: gh ist nicht angemeldet. Erst 'gh auth login'." >&2
  exit 1
}

# Muss vor dem Anstossen stehen: eine falsche Version soll nicht erst
# einen Workflowlauf kosten.
"$ROOT_DIR/scripts/check-version.sh" "$VERSION"

if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "FEHLER: Release v$VERSION existiert bereits. Version erhöhen." >&2
  exit 1
fi

printf '\n== Release v%s ==\n' "$VERSION"
printf 'Plattform : %s\n' "$PLATFORM"
printf 'Dry-Run   : %s\n' "$DRY_RUN"
printf 'Pre-Release: %s\n' "$PRERELEASE"
printf 'Tag       : v%s (wird erst beim Veroeffentlichen angelegt)\n\n' "$VERSION"

if [ "$DRY_RUN" = true ]; then
  printf 'Dry-Run – es wird nichts veroeffentlicht.\n\n'
fi

ARGS="--raw-field version=$VERSION --raw-field platform=$PLATFORM --raw-field dry_run=$DRY_RUN --raw-field prerelease=$PRERELEASE"
[ -n "$NOTES" ] && ARGS="$ARGS --raw-field notes=$NOTES"

# shellcheck disable=SC2086
gh workflow run release.yml $ARGS

printf 'Workflow gestartet.\n\n'
printf 'Fortschritt:\n'
printf '  gh run watch --exit-status\n\n'
printf 'Nach dem Lauf:\n'
printf '  gh release view v%s\n' "$VERSION"