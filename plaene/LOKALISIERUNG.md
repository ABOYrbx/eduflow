# Lokalisierung (Crowdin) — Stand und Reihenfolge

Quelle für Design-/Plattformregeln: `AGENTS.md` (dort gelten weiterhin alle
Projektgrenzen). iOS ist ausgenommen (zurückgestellt).

## Stand: Quellen befüllt, Crowdin kann übersetzen

Deutsch ist überall Source-Sprache **und** Fallback. Alle nutzersichtbaren
UI-Strings liegen in Quelldateien und erscheinen nach dem nächsten Sync in
Crowdin. Für macOS liegen englische Übersetzungen bereits im Katalog
(Branch `l10n/xcstrings-all-languages`); für Web/Backend/Android liefert
Crowdin später nur Ergänzungen, kein Verhalten ändert sich. Die API-Fehler-`code`s werden nie
übersetzt — nur die `error`-Texte.

## Dateizuordnung (`crowdin.yml` im Root)

| Plattform | Quelle im Repo (deutsch) | Übersetzung via Crowdin |
|---|---|---|
| Web (Next.js) | `apps/web/messages/de.json` (`t()` aus `src/lib/i18n.ts`) | `apps/web/messages/<locale>.json` |
| Backend (NestJS) | `apps/api/src/messages/de.json` (`t()` aus `src/i18n.ts`) | `apps/api/src/messages/<locale>.json` |
| Android | `android/app/src/main/res/values/strings.xml` (`stringResource`) | `res/values-<android_code>/strings.xml` |
| macOS | `mac/EduFlow/Resources/Localizable.xcstrings` (Source `de`, im Bundle registriert) | gleiche Datei (String Catalog) |

Kennzahlen: Web ~300 Keys, Backend ~110 Keys (Fehlertexte, Settings-Schema,
API-Docs), Android ~310 Strings + 3 Plurals, macOS 275 Katalog-Keys
(Source-Sprache `de`) plus Übersetzungen für alle UI-Texte auf Englisch,
Türkisch, Polnisch und Französisch (Status-/Typ-/Aktions-Codes bleiben
bewusst deutsch, siehe unten; Branch `l10n/xcstrings-all-languages`).

## Sync-Ablauf

- Quellen → Crowdin: automatisch (GitHub-App syncet `main` laufend; Action
  `upload-sources` lädt bei Push mit geänderten Quellen zusätzlich hoch).
- Übersetzungen → Repo: automatisch per Sync-Schedule der GitHub-App als PR
  (Review-Pflicht, kein Auto-Merge). Der Download-Job der Action ist entfernt,
  damit nicht zwei Bots konkurrierende PRs erzeugen.
- `update_option: update_as_unapproved` erhält Übersetzungen bei kleinen
  Quelltext-Korrekturen (z. B. Tippfehler).
- Sync-Commits der App enthalten `[ci skip]` (Crowdin-Standard).
- Secrets: `CROWDIN_PROJECT_ID` + `CROWDIN_TOKEN` als GitHub-Secrets, nie im
  Repo, nie in `.env` committen.

## Was du manuell in Crowdin / GitHub tun musst

1. Crowdin-Projekt anlegen (privat, Source-Sprache Deutsch). ✅ (erledigt)
2. Crowdin-GitHub-App für `ABOYrbx/eduflow` installieren (nur `main`,
   Service-Branch `l10n_main`, Sync-Schedule täglich). ✅ (erledigt)
3. In GitHub unter Settings → Secrets: `CROWDIN_PROJECT_ID` und
   `CROWDIN_TOKEN` (feingranular, nur das eine Projekt) anlegen. ⏳ (offen)
4. Erste Zielsprache freischalten, Sync in Actions prüfen, ersten
   Übersetzungs-PR reviewen und mergen.

## Bewusst ausgenommen (kein Übersetzungsbedarf)

- **Protokoll-Strings:** Hausaufgaben-Status (`überfällig`, `heute fällig`,
  …), Typ-Codes und `code`-Vokabular steuern Filter/Vergleiche in allen
  Clients — sie bleiben deutsch und stabil. Echte Mehrsprachigkeit braucht
  später Status-Codes als eigenes Feld (Follow-up, API-Änderung).
- **Datums-/Zeitformate** (`Mittwoch · 20:01`, `Woche …`, `day_label`):
  werden pro Locale formatiert (Follow-up: `Intl`), nicht übersetzt.
- **EduPage-Domain-Labels** (`TYPE_LABELS`, Monats-/Wochentagsnamen,
  `serializers.ts`): Daten-Mapping, kein UI-Text.
- **Demo-Inhalte** (Fake-Provider, `demo-data.ts`): simulierte Schul-Daten.
- **Wetterbeschreibungen** (`desc`): Fremddaten von OpenWeather.
- **Android-ViewModel-Fallbacks** (`ErrorMapper`, `*ViewModel`): brauchen
  Context; Tests erzwingen Deutsch.
- **macOS-`value:`-Fallbacks:** identischer deutscher Text, greift nur wenn
  der Katalog fehlt.

## Regeln für neue Strings (PR-Checkliste)

1. Neue UI-Strings gehören immer in die Quelldatei der Plattform
   (keine Hardcodings): Web → `messages/de.json`, Backend → `src/messages/de.json`,
   Android → `values/strings.xml`, macOS → `xcstrings` (+ `NSLocalizedString`
   bei dynamischen Stellen).
2. `code`-Vokabular und Status-/Typ-Werte stabil halten (siehe oben).
3. Web: Neue Crowdin-Sprache = Import + Eintrag in `apps/web/src/lib/locales.ts`
   ergänzen (sonst fällt `t()` auf Deutsch zurück); Katalog-Änderungen brauchen
   einen Web-Rebuild (JSONs sind gebündelt). Neue UI-Strings brauchen nur
   `de.json` — andere Kataloge fallen pro Key auf Deutsch zurück.
4. Abnahmen: `npm test` + `npm run typecheck` (Root), Gradle
   `:app:assembleDebug :app:testDebugUnitTest`, `xcodebuild … test`.
