#!/usr/bin/env sh
# Erzeugt den Release-Keystore fuer die Android-CI und verrät die Secrets.
#
# Der Keystore entsteht NUR lokal und wird als base64-Secret nach GitHub
# hochgeladen – nie committet. `*.jks` und `*.keystore` stehen bereits in
# .gitignore, zusätzlich prüft das Skript das noch einmal.
#
# Aufruf:
#   scripts/generate-android-keystore.sh                       # interaktiv
#   OUT_DIR=~/keys scripts/generate-android-keystore.sh        # woanders ablegen
#
# Danach in GitHub als Repository-Secret hinterlegen:
#   ANDROID_KEYSTORE_BASE64   -> base64-Inhalt der .jks
#   ANDROID_KEYSTORE_PASSWORD -> das Store-Passwort
#   ANDROID_KEY_ALIAS         -> der Alias (Standard: eduflow-release)
#   ANDROID_KEY_PASSWORD      -> das Key-Passwort
set -eu

ALIAS="${ALIAS:-eduflow-release}"
VALIDITY_DAYS="${VALIDITY_DAYS:-10000}"   # ~27 Jahre, uebersteht jede Play-Regel
OUT_DIR="${OUT_DIR:-$PWD}"
KEYSTORE="$OUT_DIR/eduflow-release.jks"

command -v keytool >/dev/null 2>&1 || {
  echo "FEHLER: keytool nicht gefunden. Java 17+ (JDK) installieren." >&2
  exit 1
}

echo "== EduFlow Release-Keystore =="
echo "Ziel : $KEYSTORE"
echo "Alias: $ALIAS"
echo

if [ -z "${EDUFLOW_KEYSTORE_PASSWORD:-}" ]; then
  printf 'Passwort fuer den Keystore (leer = Zufallswert): '
  stty -echo 2>/dev/null || true
  IFS= read -r EDUFLOW_KEYSTORE_PASSWORD
  stty echo 2>/dev/null || true
  printf '\n'
fi
GENERATED=false
if [ -z "${EDUFLOW_KEYSTORE_PASSWORD:-}" ]; then
  EDUFLOW_KEYSTORE_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
  GENERATED=true
fi

# PKCS12 kann KEINE getrennten Store-/Key-Passwörter: keytool ignoriert
# -keypass mit einer Warnung. Es gibt also nur ein Passwort. Wird später
# auf JKS umgestellt, braucht es hier wieder zwei Werte.
if [ -z "${EDUFLOW_KEY_PASSWORD:-}" ]; then
  EDUFLOW_KEY_PASSWORD="$EDUFLOW_KEYSTORE_PASSWORD"
fi

# WICHTIG: Ein selbst erzeugtes Passwort muss sichtbar sein. Ein leeres
# Secret auf GitHub ist kein Passwort, sondern ein Leerstring – der
# Release-Workflow laeuft dann mit leerem Passwort gegen die Keytool-Prompt
# und bricht ab. Deshalb hier bewusst Klartext (steht nur im Terminal des
# Erzeugenden, nie im Repo).
if [ "$GENERATED" = true ]; then
  printf '\n====================================================\n'
  printf '  Zufallspasswort erzeugt – BITTE NOTIEREN\n'
  printf '\n'
  printf '  %s\n' "$EDUFLOW_KEYSTORE_PASSWORD"
  printf '\n'
  printf '  Ohne dieses Passwort sind spaetere Updates auf diesem\n'
  printf '  Signing-Key nicht mehr installierbar.\n'
  printf '====================================================\n\n'
fi

if [ -f "$KEYSTORE" ]; then
  echo "FEHLER: $KEYSTORE existiert bereits. Ohne Backup wuerde ein Release," >&2
  echo "        das darauf signiert ist, danach nicht mehr updatebar sein." >&2
  exit 1
fi

keytool -genkeypair \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity "$VALIDITY_DAYS" \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -storepass "$EDUFLOW_KEYSTORE_PASSWORD" \
  -keypass "$EDUFLOW_KEY_PASSWORD" \
  -dname "CN=EduFlow, OU=EduFlow, O=EduFlow, L=, ST=, C=DE"

chmod 600 "$KEYSTORE"

printf '\n== Fertig ==\n'
printf 'Datei: %s\n\n' "$KEYSTORE"
printf 'SOFORT sichern. Geht der Keystore verloren, sind spaetere Updates\n'
printf 'auf diesem signing key nicht mehr installierbar.\n\n'
printf 'Nur die base64-Ausgabe gehoert nach GitHub, nicht die .jks:\n\n'
printf '  gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 <%%s | tr -d "\\n")\n' "$KEYSTORE"
printf '  gh secret set ANDROID_KEYSTORE_PASSWORD   # Wert oben eintragen\n'
printf '  gh secret set ANDROID_KEY_ALIAS          # %s\n' "$ALIAS"
printf '  gh secret set ANDROID_KEY_PASSWORD       # Wert oben eintragen\n\n'
printf 'Git-Status pruefen (darf den Keystore nicht zeigen):\n'
printf '  git status --porcelain\n'