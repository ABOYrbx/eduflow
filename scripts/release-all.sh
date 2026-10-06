#!/usr/bin/env sh
# ============================================================================
# EduFlow — Release-Durchlaufe in einem Skript
# ============================================================================
#
# Erledigt den kompletten Weg von der einmaligen Einrichtung bis zum
# veroeffentlichten Release:
#
#   0  Voraussetzungen pruefen (gh, keytool, git, sauberer Baum)
#   1  Versionen abgleichen (VERSION <-> Android <-> macOS)
#   2  Android-Secrets erzeugen und hochladen (Keystore)
#   3  macOS pruefen (ad-hoc signiert, kein Apple-Programm noetig)
#   4  Aenderungen committen und pushen (mit Rueckfrage)
#   5  Release-Workflow anstossen
#   6  Lauf verfolgen und Ergebnis anzeigen
#
# Das Skript ist idempotent: existiert ein Secret schon, wird es uebersprungen,
# existiert der Keystore schon, wird er nicht neu erzeugt. Also mehrfach
# ausfuehrbar, ohne etwas zu zerstoeren.
#
# Aufruf:
#   scripts/release-all.sh                    # alles, Version aus VERSION
#   scripts/release-all.sh 0.1.0
#   scripts/release-all.sh 0.1.0 --dry-run     # bauen, nichts veroeffentlichen
#   scripts/release-all.sh 0.1.0 --plan        # nur zeigen, nichts tun
#   scripts/release-all.sh 0.1.0 --android
#   scripts/release-all.sh 0.1.0 --macos
#   scripts/release-all.sh 0.1.0 --no-commit --no-watch
#   scripts/release-all.sh 0.1.0 --notes "Erste Version" --final
#
# WICHTIG: Nichts wird getaggt oder veroeffentlicht, ohne dass --dry-run
# NICHT gesetzt ist. Phase 5 und 6 fragen vorher noch einmal nach.
#
# Secrets werden nie im Log ausgegeben, nie per --body uebergeben (das waere
# ueber `ps` sichtbar), sondern immer ueber stdin an `gh secret set`.
# ============================================================================

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

# ---------------------------------------------------------------- Argumente
VERSION=""
PLATFORM=both
DRY_RUN=false
PLAN=false
DO_COMMIT=true
DO_WATCH=true
PRERELEASE=true
NOTES=""
SKIP_ANDROID_SECRETS=false
FORCE_SECRETS=false

while [ $# -gt 0 ]; do
  case "$1" in
    --android)        PLATFORM=android ;;
    --macos)          PLATFORM=macos ;;
    --both)           PLATFORM=both ;;
    --dry-run)        DRY_RUN=true ;;
    --plan)           PLAN=true ;;
    --no-commit)      DO_COMMIT=false ;;
    --no-watch)       DO_WATCH=false ;;
    --final)          PRERELEASE=false ;;
    --skip-android-secrets) SKIP_ANDROID_SECRETS=true ;;
    --force-secrets)  FORCE_SECRETS=true ;;
    --notes)
      shift
      [ $# -gt 0 ] || { echo "FEHLER: --notes braucht einen Text." >&2; exit 2; }
      NOTES="$1"
      ;;
    --notes=*)        NOTES="${1#--notes=}" ;;
    -h|--help)
      sed -n '2,40p' "$0"
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

# ------------------------------------------------------------------ Ausgabe
if [ -t 1 ]; then
  C_RESET=$(printf '\033[0m'); C_BOLD=$(printf '\033[1m')
  C_BLUE=$(printf '\033[34m'); C_GREEN=$(printf '\033[32m')
  C_YELLOW=$(printf '\033[33m'); C_RED=$(printf '\033[31m')
else
  C_RESET=''; C_BOLD=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''
fi

STEP_NO=0
step()  { STEP_NO=$((STEP_NO + 1)); printf '\n%s== Phase %s: %s ==%s\n' "$C_BOLD$C_BLUE" "$STEP_NO" "$1" "$C_RESET"; }
ok()    { printf '%s  ok%s   %s\n' "$C_GREEN" "$C_RESET" "$1"; }
info()  { printf '       %s\n' "$1"; }
warn()  { printf '%s  ! %s %s\n' "$C_YELLOW" "$1" "$C_RESET"; }
die()   { printf '\n%sFEHLER: %s%s\n' "$C_RED$C_BOLD" "$1" "$C_RESET" >&2; exit 1; }
todo()  { printf '%s  - %s %s\n' "$C_BLUE" "$1" "$C_RESET"; }
plan()  { printf '  %sPlan%s  %s\n' "$C_BLUE" "$C_RESET" "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

ask_yes_no() {
  # $1 = Frage, $2 = Standard (yes/no)
  _default="$2"
  if [ "$PLAN" = true ]; then return 0; fi
  if [ ! -t 0 ]; then
    printf '\n  %s (kein TTY, nehme "%s")%s\n' "$1" "$_default" "$C_RESET"
    [ "$_default" = "yes" ] && return 0 || return 1
  fi
  _hint="y/N"; [ "$_default" = "yes" ] && _hint="Y/n"
  printf '\n  %s [%s] ' "$1" "$_hint"
  read -r _answer
  [ -z "$_answer" ] && _answer="$_default"
  case "$_answer" in y|Y|yes|Ja|ja) return 0 ;; *) return 1 ;; esac
}

ask_secret() {
  # $1 = Bezeichnung, $2 = Name der Umgebungsvariable als Notausgang.
  printf '  %s: ' "$1"
  if [ -t 0 ]; then
    stty -echo 2>/dev/null || true
    IFS= read -r _secret
    stty echo 2>/dev/null || true
    printf '\n'
    [ -n "$_secret" ] || die "'$1' darf nicht leer sein."
    printf '%s' "$_secret"
  else
    printf '\n'
    die "Kein TTY: '$1' muss als $2 gesetzt werden
       (z. B. $2=… scripts/release-all.sh … – nicht auf der Kommandozeile,
        sonst steht der Wert im Shell-Verlauf)."
  fi
}

base64_nl() {
  # base64 ohne Zeilenumbrueche – BSD und GNU brauchen verschiedene Schalter.
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0 < "$1"
  else
    base64 < "$1" | tr -d '\n'
  fi
}

# ============================================================================
step "Voraussetzungen"
# ============================================================================

have gh      || die "GitHub CLI (gh) fehlt. Installieren und 'gh auth login' ausfuehren."
have git     || die "git fehlt."
have keytool || die "keytool fehlt. Java 17+ (JDK) installieren."
gh auth status >/dev/null 2>&1 || die "gh ist nicht angemeldet. Erst 'gh auth login'."
ok "gh $(gh --version | head -1 | awk '{print $3}') angemeldet"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "?")
info "Repository: $REPO"

if [ "$PLAN" != true ] && [ "$DRY_RUN" != true ]; then
  if ! git diff --quiet || [ -n "$(git status --porcelain)" ]; then
    info "Arbeitsbaum hat Aenderungen (Phase 4 commit/push optional)"
  else
    info "Arbeitsbaum sauber"
  fi
else
  info "$(git status --porcelain | wc -l | tr -d ' ') geaenderte Pfade im Arbeitsbaum"
fi

# ============================================================================
step "Version bestimmen und abgleichen"
# ============================================================================

if [ -z "$VERSION" ]; then
  [ -f VERSION ] || die "Keine Version angegeben und VERSION fehlt."
  VERSION=$(tr -d ' \t\n\r' < VERSION)
fi
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || die "Version '$VERSION' muss x.y.z sein (ohne fuehrendes v)."

TAG="v$VERSION"
"$ROOT_DIR/scripts/check-version.sh" "$VERSION"
ok "Version $VERSION, Tag $TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  die "Release $TAG existiert bereits. Version erhoehen – ein Tag wird nie ueberschrieben."
fi
# Auch verwaiste Tags ohne Release aufspueren: gh release create wuerde
# bei einem vorhandenen Tag mit einem leeren Exit abbrechen, ohne Datei.
if gh api "repos/$REPO/git/refs/tags/$TAG" >/dev/null 2>&1; then
  die "Tag $TAG existiert bereits (verwaist, ohne Release).
       Nachziehen:  gh release create $TAG --generate-notes
       Oder loeschen: git push origin :refs/tags/$TAG"
fi
info "Tag $TAG ist frei"

if [ "$PLAN" = true ]; then
  plan "Release veroeffentlichen als ${TAG}$([ "$PRERELEASE" = true ] && printf ' (Pre-Release)' || printf ' (final)')"
fi

# ============================================================================
step "Android-Secrets (Keystore)"
# ============================================================================

# PKCS12 hat nur ein Passwort (keytool ignoriert -keypass), darum drei
# und nicht vier Secrets. Beim Wechsel auf JKS kommt ANDROID_KEY_PASSWORD
# hier dazu.
ANDROID_SECRETS="ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS"
KEYSTORE_FILE="${EDUFLOW_KEYSTORE_PATH:-$ROOT_DIR/eduflow-release.jks}"

gh_secret_exists() { gh secret list 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

set_secret() {
  # $1 = Name, $2 = Wert. Wert geht ueber stdin, nie ueber --body.
  _name="$1"; _value="$2"
  if [ "$PLAN" = true ]; then plan "Secret $_name setzen"; return 0; fi
  printf '%s' "$_value" | gh secret set "$_name" >/dev/null
  ok "Secret $_name gesetzt"
}

if [ "$PLATFORM" = "macos" ]; then
  SKIP_ANDROID_SECRETS=true
  info "nur macOS gewaehlt – Android-Secrets werden uebersprungen"
fi

if [ "$SKIP_ANDROID_SECRETS" = true ]; then
  todo "uebersprungen (--skip-android-secrets)"
else
  if [ -f "$KEYSTORE_FILE" ]; then
    ok "Keystore vorhanden: $KEYSTORE_FILE"
  else
    info "Keystore fehlt – wird erzeugt"
    if [ "$PLAN" = true ]; then
      plan "Keystore erzeugen: $KEYSTORE_FILE"
    else
      # Passwort VOR dem Generator sicherstellen. Sonst erfindet der
      # Generator ein eigenes, das dieser Prozess nicht kennt – und es
      # müsste ein zweites Mal abgefragt werden. Entweder interaktiv
      # oder zufällig; in beiden Fällen steht es genau einmal im Terminal.
      GENERATED_PASSWORD=false
      if [ -z "${EDUFLOW_KEYSTORE_PASSWORD:-}" ]; then
        if [ -t 0 ]; then
          EDUFLOW_KEYSTORE_PASSWORD=$(ask_secret "Passwort fuer den neuen Keystore (leer = Zufall)" "EDUFLOW_KEYSTORE_PASSWORD")
          [ -n "$EDUFLOW_KEYSTORE_PASSWORD" ] || {
            EDUFLOW_KEYSTORE_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
            GENERATED_PASSWORD=true
          }
        else
          EDUFLOW_KEYSTORE_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
          GENERATED_PASSWORD=true
        fi
      fi
      EDUFLOW_KEYSTORE_PASSWORD="$EDUFLOW_KEYSTORE_PASSWORD" \
        "$ROOT_DIR/scripts/generate-android-keystore.sh"
      [ -f "$KEYSTORE_FILE" ] || die "Keystore wurde nicht erzeugt."
      ok "Keystore erzeugt: $KEYSTORE_FILE"
      if [ "$GENERATED_PASSWORD" = true ]; then
        printf '\n====================================================\n'
        printf '  Zufallspasswort – BITTE NOTIEREN\n\n'
        printf '  %s\n' "$EDUFLOW_KEYSTORE_PASSWORD"
        printf '\n'
        printf '  Ohne dieses Passwort sind spaetere Updates auf diesem\n'
        printf '  Signing-Key nicht mehr installierbar.\n'
        printf '====================================================\n\n'
      fi
    fi
  fi

  # Passwort nur erfragen, wenn es wirklich fehlt – ein Release soll ohne
  # Nachfrage laufen, wenn die Secrets einmal gesetzt sind.
  NEED_PASS=false
  if [ "$FORCE_SECRETS" = true ]; then
    NEED_PASS=true
  else
    for _s in $ANDROID_SECRETS; do
      gh_secret_exists "$_s" || NEED_PASS=true
    done
  fi

  if [ "$NEED_PASS" = false ]; then
    ok "alle drei Android-Secrets sind bereits gesetzt"
  elif [ "$PLAN" = true ]; then
    plan "Android-Secrets hochladen (3)"
  else
    [ -n "${EDUFLOW_KEYSTORE_PASSWORD:-}" ] || EDUFLOW_KEYSTORE_PASSWORD=$(ask_secret "Passwort des Keystores (bereits erzeugt?)" "EDUFLOW_KEYSTORE_PASSWORD")
    [ -n "${EDUFLOW_KEY_ALIAS:-}" ]         || EDUFLOW_KEY_ALIAS="eduflow-release"
    for _s in $ANDROID_SECRETS; do
      if gh_secret_exists "$_s" && [ "$FORCE_SECRETS" != true ]; then
        info "Secret $_s existiert – uebersprungen (--force-secrets zum Ueberschreiben)"
      else
        case "$_s" in
          ANDROID_KEYSTORE_BASE64)   set_secret "$_s" "$(base64_nl "$KEYSTORE_FILE")" ;;
          ANDROID_KEYSTORE_PASSWORD) set_secret "$_s" "$EDUFLOW_KEYSTORE_PASSWORD" ;;
          ANDROID_KEY_ALIAS)         set_secret "$_s" "$EDUFLOW_KEY_ALIAS" ;;
        esac
      fi
    done
  fi
fi

# ============================================================================
step "macOS-Signatur (bewusst ad-hoc)"
# ============================================================================

if [ "$PLATFORM" = "android" ]; then
  info "nur Android gewaehlt"
else
  # Kein Apple-Programm, kein Developer-ID-Zertifikat, keine Notarisierung.
  # Die App wird ad-hoc signiert (CODE_SIGN_IDENTITY = "-"), wie im Projekt
  # hinterlegt – dazu sind keine Secrets noetig.
  ok "keine macOS-Secrets noetig (ad-hoc signiert, ohne Apple-Programm)"
  if gh secret list 2>/dev/null | grep -qE '^MACOS_|^APPLE_'; then
    info "verwaiste macOS-Secrets im Repo vorhanden – werden nicht mehr gelesen,"
    info "konnen aber mit 'gh secret delete <NAME>' entfernt werden."
  fi
  if [ "$PLAN" = true ]; then
    plan "macOS ad-hoc signieren, DMG + ZIP bauen, nicht notarisiert"
  fi
  info "Nutzer muessen die App einmalig per Rechtsklick > Oeffnen freigeben (Gatekeeper)"
fi


step "Aenderungen committen und pushen"
# ============================================================================

CHANGED=$(git status --porcelain)
if [ -z "$CHANGED" ]; then
  info "nichts zu committen"
elif [ "$DO_COMMIT" != true ]; then
  todo "uebersprungen (--no-commit)"
elif [ "$PLAN" = true ]; then
  plan "committen: $(printf '%s' "$CHANGED" | wc -l | tr -d ' ') Pfade"
elif [ "$DRY_RUN" = true ]; then
  todo "uebersprungen (--dry-run)"
else
  info "Geaenderte Pfade:"
  printf '%s\n' "$CHANGED" | sed 's/^/         /'
  if ask_yes_no "Committen und nach $REPO pushen?" "yes"; then
    BRANCH=$(git branch --show-current)
    git add -A
    git commit -q -m "ci: Release-Pipeline fuer Android und macOS" \
      -m "Fuehrt ein Release nur noch manuell aus. Version kommt aus VERSION
und wird gegen Android und macOS geprueft. Android signiert, macOS ad-hoc
ohne Apple-Programm. Details in .github/RELEASING.md." || die "Commit fehlgeschlagen."
    ok "commit $(git rev-parse --short HEAD) auf $BRANCH"
    git push -q origin "$BRANCH" || die "Push fehlgeschlagen."
    ok "gepusht nach origin/$BRANCH"
  else
    info "uebersprungen"
  fi
fi

# ============================================================================
step "Release-Workflow anstossen"
# ============================================================================

if [ "$PLAN" = true ]; then
  plan "gh workflow run release.yml -f version=$VERSION -f platform=$PLATFORM"
  plan "dry_run=$DRY_RUN prerelease=$PRERELEASE"
  printf '\n%sPlan vollstaendig. Es wurde nichts geaendert.%s\n' "$C_BOLD" "$C_RESET"
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  info "Dry-Run: es wird gebaut, aber nichts veroeffentlicht."
elif ! ask_yes_no "Release $TAG jetzt ausloesen?" "no"; then
  info "abgebrochen – nichts veroeffentlicht"
  exit 0
fi

# Vorher pruefen, ob der Workflow ueberhaupt existiert. Sonst gibt
# `gh workflow run` nur ein nacktes HTTP 404 aus, das sich nicht
# interpretieren laesst.
if ! gh workflow view release.yml >/dev/null 2>&1; then
  die "Workflow 'release.yml' existiert auf $REPO nicht (oder ist noch nicht gepusht).
       Die Workflow-Dateien muessen erst auf dem Default-Branch liegen:
         git add .github scripts VERSION
         git commit -m 'ci: Release-Pipeline'
         git push"
fi

# Erste Secret-Schreiboperation des Laufs klar ankündigen, damit nie
# unbemerkt im falschen Repository landet.
if [ "$STEP_NO" = 5 ] && [ "$DRY_RUN" != true ]; then
  warn "Es werden Secrets in $REPO geschrieben bzw. übersprungen."
fi

gh workflow run release.yml \
  --raw-field "version=$VERSION" \
  --raw-field "platform=$PLATFORM" \
  --raw-field "dry_run=$DRY_RUN" \
  --raw-field "prerelease=$PRERELEASE" \
  ${NOTES:+--raw-field "notes=$NOTES"}
ok "Workflow gestartet"

# ============================================================================
step "Lauf verfolgen"
# ============================================================================

RUN_ID=""
i=0
while [ $i -lt 12 ]; do
  i=$((i + 1))
  RUN_ID=$(gh run list --workflow release.yml --limit 1 --json databaseId,headBranch -q '.[0].databaseId' 2>/dev/null || echo "")
  [ -n "$RUN_ID" ] && break
  sleep 2
done
[ -n "$RUN_ID" ] || warn "Konnte den Lauf nicht finden – siehe 'gh run list'."

if [ -n "$RUN_ID" ] && [ "$DO_WATCH" = true ]; then
  info "warte auf Lauf $RUN_ID (Strg+C bricht nur das Zusehen ab)"
  if gh run watch "$RUN_ID" --exit-status; then
    ok "Lauf erfolgreich"
  else
    warn "Lauf fehlgeschlagen – Logs: gh run view $RUN_ID --log-failed"
  fi
fi

printf '\n%s== Ergebnis ==%s\n' "$C_BOLD" "$C_RESET"
if [ "$DRY_RUN" = true ]; then
  info "Dry-Run: nichts veroeffentlicht, Tag $TAG existiert nicht."
else
  gh release view "$TAG" 2>/dev/null | sed 's/^/       /' || info "Release $TAG ansehen: gh release view $TAG"
fi