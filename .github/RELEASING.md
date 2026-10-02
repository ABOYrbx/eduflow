# Releasing

EduFlow released **nicht automatisch**. Es gibt keinen `push`- und keinen
`tag`-Trigger. Ein Release entsteht nur, wenn jemand ausdrücklich sagt
„release 0.1.0" und der Lauf manuell angestossen wird. Solange das Projekt
früh ist, bleibt die Versionsnummer so unter Kontrolle.

```
scripts/release.sh 0.1.0            # baut, signiert, veröffentlicht
scripts/release.sh 0.1.0 --dry-run  # baut, veröffentlicht aber nichts
```

## Das eine Skript

`scripts/release-all.sh` macht den kompletten Weg: Voraussetzungen prüfen,
Versionen abgleichen, Secrets erzeugen und hochladen, committen, pushen,
Workflow anstoßen, Lauf verfolgen. Idempotent — existiert ein Secret schon,
wird es übersprungen.

```sh
scripts/release-all.sh                    # alles, Version aus VERSION
scripts/release-all.sh 0.1.0 --dry-run     # baut, veröffentlicht nichts
scripts/release-all.sh 0.1.0 --plan        # nur zeigen, nichts tun
scripts/release-all.sh 0.1.0 --android     # nur eine Plattform
```

Für den ersten Lauf **`--plan`**, dann **`--dry-run`**, dann der echte Lauf.
Ein angefangener Teilstand lässt sich mit `--skip-android-secrets`
weiterführen. Nicht-interaktiv (Cron, CI) geht über Umgebungsvariablen:

```sh
EDUFLOW_KEYSTORE_PASSWORD=… scripts/release-all.sh 0.1.0
```

Passwörter gehören **nicht** auf die Kommandozeile, sonst stehen sie im
Shell-Verlauf. macOS braucht kein Skript und kein Konto: ad-hoc signiert (siehe unten).

Die einzelnen Schritte bleiben auch einzeln nutzbar: `scripts/check-version.sh`,
`scripts/generate-android-keystore.sh`, `scripts/release.sh`.

## Vorbedingungen (einmalig)

### 1. Android-Keystore

```sh
scripts/generate-android-keystore.sh
```

Erzeugt lokal `eduflow-release.jks` (Alias `eduflow-release`, RSA 4096,
gültig ~27 Jahre) und druckt die drei Secrets. **Den Keystore sofort
wegsichern** — ohne ihn sind spätere Updates auf diesem Signing-Key nicht
mehr installierbar. Er wird nie committet (`*.jks` steht in `.gitignore`).

```sh
base64 < eduflow-release.jks | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS          # eduflow-release
```

Oder einfach `scripts/release-all.sh` — das macht das automatisch.

### 2. macOS: nichts einzustellen

Kein Apple-Programm, kein Developer-ID-Zertifikat, keine Notarisierung. Die
macOS-App wird **ad-hoc** signiert (`CODE_SIGN_IDENTITY = "-"`), so wie das
Projekt ohnehin lokal baut. Das ist eine echte Signatur, aber keine
*Vertrauens*signatur — deshalb blockiert Gatekeeper den ersten Start.

Nutzer müssen die App einmalig freigeben:

1. DMG öffnen, `EduFlow.app` nach „Programme" ziehen
2. `EduFlow` **rechts anklicken** → **Öffnen** → **Öffnen**

Ab dann startet sie normal. Alternativ ohne Gatekeeper-Dialog:

```sh
xattr -dr com.apple.quarantine /Applications/EduFlow.app
```

**Was das kostet und was nicht:** Für Endnutzer ein Klick, kein Account, kein
Kauf. Nur macOS/Xcode muss zum *Bauen* vorhanden sein – auf dem Runner ist das
der Fall. Wer die App später ohne diese Freigabe-Klick an Fremde verteilt oder
im Mac App Store anbieten will, braucht doch ein Apple-Programm. Das ist eine
Entscheidung, jederzeit änderbar, ohne Code anzufassen: der Release-Job
enthält die Notarisierung nur noch nicht.

## Secrets im Überblick

Nur die **Android**-Plattform braucht Secrets:

| Secret | Zweck |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Keystore als base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Passwort des Keystores |
| `ANDROID_KEY_ALIAS` | Key-Alias (`eduflow-release`) |

**Warum nur ein Passwort?** Der Keystore ist **PKCS12**, und PKCS12 kennt keine
getrennten Store- und Key-Passwörter — `keytool` ignoriert `-keypass` und
warnt: *„Keine Unterstützung für unterschiedliche Speicher- und
Schlüsselkennwörter bei PKCS12 KeyStores."* Es gibt also technisch nur eins.
Wird später auf JKS umgestellt, kommt `ANDROID_KEY_PASSWORD` dazu.

Keines wird geloggt; der Keystore wird nur im Arbeitsspeicher des Runners
materialisiert, nie über `--body` (das wäre über `ps` sichtbar). Passwörter
gehören nicht auf die Kommandozeile, sonst stehen sie im Shell-Verlauf.

**macOS braucht bewusst keine Secrets.** Kein Developer-Account, kein
Zertifikat, keine Notarisierung. Siehe unten.

## Versionspflege

`VERSION` im Repo-Root ist die führende Quelle. `scripts/check-version.sh`
vergleicht sie mit `android/app/build.gradle.kts` und dem
`MARKETING_VERSION` im macOS-Projekt und bricht bei Abweichung ab — sonst
könnte ein Tag `0.1.0` behaupten, während im Artefakt eine andere Version steht.

Für eine neue Version, z. B. 0.2.0, alle drei Stellen together ändern:

```sh
echo 0.2.0 > VERSION
# android/app/build.gradle.kts: versionName = ... ifEmpty { "0.2.0" }
# mac/…/project.pbxproj:        MARKETING_VERSION = 0.2.0 (Debug + Release)
./scripts/check-version.sh      # muss grün sein
```

Der Release-Workflow injiziert die Version beim Bauen trotzdem noch einmal per
`-PeduflowVersionName=` bzw. `MARKETING_VERSION=`, damit das Artefakt
eindeutig zum Tag gehört. `mac/EduFlow/Info.plist` liest die Version
inzwischen aus `$(MARKETING_VERSION)` statt hart.

## Was ein Lauf produziert

| Plattform | Artefakt | Signatur |
|---|---|---|
| Android | `eduflow-android-0.1.0.apk` — eine universelle APK | Release-Key |
| macOS | `EduFlow-0.1.0.dmg` und `EduFlow-0.1.0.zip` | ad-hoc, ohne Apple-Account |

Veröffentlicht wird als GitHub-Release mit Tag `v0.1.0`, standardmäßig als
**Pre-Release** (`--final` schaltet das ab).

## CI ohne Release

Zwei weitere Workflows laufen bei jedem Push auf `main` und jedem PR gegen die
jeweiligen Plattformordner, völlig ohne Secrets:

- `android-ci.yml` — `:app:assembleDebug :app:testDebugUnitTest` (offline, Fake-`ApiService`)
- `macos-ci.yml` — `xcodebuild test` (offline, URL-Stubs)

Erst wenn beide und `npm run typecheck` + `npm test` grün sind, lohnt sich ein
Release.

## Fehlerbilder

**„Release signing required but no keystore"** — die Keystore-Secrets fehlen.
Der Release-Workflow setzt `-PeduflowRequireReleaseSigning=true` und bricht
dann ab, statt still einen debug-signierten APK zu veröffentlichen.

**Gatekeeper blockiert die macOS-App** — erwartet, weil nicht notarisiert.
Siehe [macOS: nichts einzustellen](#2-macos-nichts-einzustellen).

**Tag-Konflikt** — `v0.1.0` existiert schon. Version erhöhen; ein Release-Tag
wird nicht überschrieben, damit Builds reproduzierbar bleiben.

**Zip-Fehler „damaged" beim Entpacken auf einem anderen Mac** — nicht `zip`,
sondern immer `ditto` verwenden (macht der Workflow bereits). Nur `ditto`
bewahrt die Code-Signatur.