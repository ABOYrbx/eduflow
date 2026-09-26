# Lokalisierung (Crowdin) — Stand und Reihenfolge

Quelle für Design-/Plattformregeln: `AGENTS.md` (dort gelten weiterhin alle
Projektgrenzen). iOS ist ausgenommen (zurückgestellt).

## Stand: nur Setup, keine Zielsprache

Deutsch ist überall Source-Sprache **und** Fallback. Es gibt noch keine
übersetzten UI-Texte; Crowdin liefert später nur Ergänzungen, kein Verhalten
ändert sich. Die API-Fehler-`code`s (`api/core.py`, `ERROR CODES`) werden nie
übersetzt — nur die `error`-Texte.

## Dateizuordnung (`crowdin.yml` im Root)

| Plattform | Quelle im Repo | Übersetzung via Crowdin |
|---|---|---|
| Web + Backend | `locales/templates/messages.pot` (per `pybabel extract -F babel.cfg` erzeugt) | `locales/<locale>/LC_MESSAGES/messages.po` |
| Android | `android/app/src/main/res/values/strings.xml` (deutsch) | `res/values-<android_code>/strings.xml` |
| macOS | `mac/EduFlow/Resources/Localizable.xcstrings` (Source `de`) | gleiche Datei (String Catalog) |

Ist-Zustand der Quellen: Android-`strings.xml` enthält erst `app_name`
(Compose-Texte sind noch hartkodiert), `messages.pot` ist ein Platzhalter
ohne Einträge, `Localizable.xcstrings` ist leer mit Source `de`.

## Sync-Ablauf (GitHub-Integration)

- Push auf `main` mit geänderten Quellen → Action `upload-sources` lädt hoch.
- Übersetzungen holt man per manuellem Action-Start (`workflow_dispatch`) als
  PR `l10n/crowdin-translations` → `main` (Review-Pflicht, kein Auto-Merge).
- Secrets: `CROWDIN_PROJECT_ID` + `CROWDIN_TOKEN` als GitHub-Secrets, nie im
  Repo, nie in `.env` committen.

## Was du manuell in Crowdin / GitHub tun musst

1. Crowdin-Projekt anlegen (privat, Source-Sprache Deutsch).
2. Crowdin-GitHub-App für `ABOYrbx/eduflow` installieren (nur `main` + die
   `l10n/*`-Branches freigeben).
3. In GitHub unter Settings → Secrets: `CROWDIN_PROJECT_ID` und
   `CROWDIN_TOKEN` (Feingranular-Token, nur das eine Projekt) anlegen.
4. Diese Branch mergen, Sync in Actions prüfen (Upload läuft erst bei Push
   auf `main` mit geänderten Quellen).

## Nächste Ausbauschritte (jeweils eigene Branch + Tests grün)

1. **Web/Backend:** `Flask-Babel` als Dependency begründen, `Babel(app)` mit
   `locale_selector` + Fallback `de`, alle 11 Templates + `flash()`-Texte +
   `api/*`-Meldungen auf `gettext()` umstellen, `messages.pot` echt erzeugen.
   Abnahme: `python3 tests/test_api_e2e.py` grün, UI deutsch-identisch.
2. **Android:** hartkodierte Compose-`Text("…")` nach `values/strings.xml`
   überführen (`stringResource`), Abnahme: Gradle-Unit-Tests grün.
3. **macOS:** `Text("…")` auf `LocalizedStringKey` umstellen, deutsche
   Rückfalltexte aus `APIError.swift` in den Katalog übernehmen, Abnahme:
   `xcodebuild test` (52 Tests) grün.
4. Danach erste Zielsprache in Crowdin freischalten und Download-PR testen.
5. Offene Folge-Regel für `AGENTS.md`: neue UI-Strings immer in die
   Quelldateien (keine Hardcodings), `code`-Vokabular stabil halten.
