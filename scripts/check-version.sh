#!/usr/bin/env sh
# Prüft, dass VERSION, Android und macOS dieselbe Version melden.
#
# Aufruf:
#   scripts/check-version.sh              gegen die VERSION-Datei
#   scripts/check-version.sh 0.1.0        zusätzlich gegen eine gewünschte Version
#
# Wird von den CI-Workflows und vom Release-Workflow aufgerufen. Bricht ab,
# sobald eine der drei Stellen abweicht – sonst könnte ein Release-Tag 0.1.0
# behaupten, während im Artefakt eine andere Version steht.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

fail() {
  printf 'FEHLER: %s\n' "$1" >&2
  exit 1
}

# --------------------------------------------------------------- erwartet
if [ -n "${1:-}" ]; then
  EXPECTED="$1"
else
  [ -f VERSION ] || fail "VERSION fehlt im Repo-Root."
  EXPECTED=$(tr -d ' \t\n\r' < VERSION)
fi

printf '%s' "$EXPECTED" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' \
  || fail "Version '$EXPECTED' ist keine x.y.z[-suffix]-Version."

printf 'erwartete Version: %s\n' "$EXPECTED"

# --------------------------------------------------------------- Android
ANDROID_FILE="android/app/build.gradle.kts"
ANDROID_VERSION=$(grep -oE 'ifEmpty \{ "[0-9]+\.[0-9]+\.[0-9]+" \}' "$ANDROID_FILE" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
[ -n "$ANDROID_VERSION" ] || fail "Default-VersionName in $ANDROID_FILE nicht gefunden."
[ "$ANDROID_VERSION" = "$EXPECTED" ] \
  || fail "$ANDROID_FILE meldet $ANDROID_VERSION, erwartet $EXPECTED. (oder VERSION anpassen)"
printf '  Android      %s (ok)\n' "$ANDROID_VERSION"

# --------------------------------------------------------------- macOS
PBXPROJ="mac/EduFlow Mac.xcodeproj/project.pbxproj"
MACOS_VERSION=$(grep -oE 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u | head -1)
[ -n "$MACOS_VERSION" ] || fail "MARKETING_VERSION in $PBXPROJ nicht gefunden."
[ "$MACOS_VERSION" = "$EXPECTED" ] \
  || fail "$PBXPROJ meldet $MACOS_VERSION, erwartet $EXPECTED. (oder VERSION anpassen)"
printf '  macOS        %s (ok)\n' "$MACOS_VERSION"

# --------------------------------------------------------------- Info.plist
PLIST="mac/EduFlow/Info.plist"
grep -q '<string>$(MARKETING_VERSION)</string>' "$PLIST" \
  || fail "$PLIST nutzt \$(MARKETING_VERSION) nicht – ohne das greift die CI-Injektion nicht."
printf '  Info.plist   $(MARKETING_VERSION) (ok)\n'

printf 'Versionen stimmen überein.\n'