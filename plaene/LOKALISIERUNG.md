# Lokalisierung (Crowdin) — Stand und Reihenfolge

Quelle für Design-/Plattformregeln: `AGENTS.md` (dort gelten weiterhin alle
Projektgrenzen). iOS ist ausgenommen (zurückgestellt).

## Stand: Quellen befüllt, Crowdin kann übersetzen

Deutsch ist überall Source-Sprache **und** Fallback. Alle nutzersichtbaren
UI-Strings liegen in Quelldateien und erscheinen nach dem nächsten Sync in
Crowdin. Es gibt noch keine übersetzten UI-Texte; Crowdin liefert später nur
Ergänzungen, kein Verhalten ändert sich. Die API-Fehler-`code`s werden nie
übersetzt — nur die `error`-Texte.

Android- und macOS-UI sind vollständig auf die Quelldateien umgestellt
(keine Hardcodings mehr): Android nutzt `stringResource` aus
`values/strings.xml`, macOS `LocalizedStringKey` aus dem String-Katalog.
Ausgenommen bleiben nur die unten dokumentierten Fälle
(ViewModel-Fallbacks ohne Context, Protokoll-Strings/Status,
Datumsformate, Demo-Daten) — diese bleiben bewusst deutsch.

## Dateizuordnung (`crowdin.yml` im Root)

| Plattform | Quelle im Repo (deutsch) | Übersetzung via Crowdin |
|---|---|---|
| Web (Next.js) | `apps/web/messages/de.json` (`t()` aus `src/lib/i18n.ts`) | `apps/web/messages/<locale>.json` |
| Backend (NestJS) | `apps/api/src/messages/de.json` (`t()` aus `src/i18n.ts`) | `apps/api/src/messages/<locale>.json` |
| Android | `android/app/src/main/res/values/strings.xml` (`stringResource`) | `res/values-<android_code>/strings.xml` |
| macOS | `mac/EduFlow/Resources/Localizable.xcstrings` (Source `de`, im Bundle registriert) | gleiche Datei (String Catalog) |

Kennzahlen (Blätter/Entries gezählt): Web 295 Keys (13 Gruppen),
Backend 115 Keys (Fehlertexte, Settings-Schema, API-Docs), Android 319
Strings + 3 Plurals, macOS 336 Katalog-Keys (Source-Sprache `de`).

## Sync-Ablauf

- Quellen → Crowdin: automatisch, die GitHub-App syncet `main` laufend.
  (Die frühere Sync-Action ist entfernt, die App macht alles allein.)
- Übersetzungen → Repo: automatisch per Sync-Schedule der GitHub-App als PR
  (Review-Pflicht, kein Auto-Merge).
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
3. Abnahmen: `npm test` + `npm run typecheck` (Root), Gradle
   `:app:assembleDebug :app:testDebugUnitTest`, `xcodebuild … test`.
