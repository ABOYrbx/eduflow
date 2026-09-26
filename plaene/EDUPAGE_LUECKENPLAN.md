# EduPage-Funktionslücken und möglicher Ausbauplan

## Ziel und Abgrenzung

EduFlow enthält bereits zentrale Schüler-/Elternfunktionen: Nachrichten,
Hausaufgaben, Stundenplan, Noten, Essensplan sowie Übersicht und Wetter. Die
Bereichspläne und der vorhandene API-Vertrag dokumentieren den aktuellen
Projektumfang.

„EduPage vollständig klonen“ kann mehr bedeuten als eine Schüler-App: EduPage
ist eine umfangreiche, konfigurierbare Schulplattform mit Schüler-, Eltern-,
Lehrkräfte- und Verwaltungsfunktionen. Die hier empfohlene erste Zielmarke ist
deshalb **möglichst vollständige Parität für eine einzelne Schüler-/Elternrolle**.
Ein vollständiger Ersatz der Schulverwaltung wäre ein eigener, deutlich größerer
Projektumfang und widerspräche mehreren aktuellen Projektgrenzen.

Die öffentlich beschriebenen Funktionen belegen, welche Module EduPage anbietet;
sie belegen nicht, dass die von EduFlow verwendete EduPage-Bibliothek bzw. das
aktuelle Backend diese Daten bereits abrufen oder ändern kann. Vor jeder
Implementierung muss die technische Verfügbarkeit anhand der bestehenden
Integration und sicherer, anonymisierter Testdaten geprüft werden.

## Bestehende Abdeckung

- Nachrichten, Threads, Likes, Antworten, Empfänger und Anhänge
- Hausaufgaben, Erledigt-Status und lokaler Papierkorb
- Stundenplan als Tages- und Wochenansicht
- Noten und Fächerübersicht
- Wochen-Essensplan (derzeit Anzeige, keine Bestellung)
- Übersicht, Wetter, Einstellungen und Geräteverwaltung
- Android, macOS und Web als aktuelle Fokusflächen; iOS ist zurückgestellt

## Lücken nach Priorität

### Priorität 1 — Kerninformationen für Schüler und Eltern

**Lesender Teil ergänzt:** Vertretungen sowie Timeline-Einträge für
Schulereignisse, Prüfungen und Anwesenheit sind über `/termine` und die
Android-/macOS-Ansichten erreichbar. Die Daten liegen außerdem unter
`GET /api/v1/substitutions/week` und `GET /api/v1/school/agenda` bereit.
Abwesenheit melden/entschuldigen und Statusänderungen schreiben sind damit
nicht abgedeckt; dafür muss eine unterstützte EduPage-Schreibschnittstelle
verifiziert werden.

1. **Anwesenheit und Abwesenheiten**
   - Fehlzeiten, Verspätungen und Anwesenheitsübersicht anzeigen
   - Abwesenheits-/Krankmeldung einreichen und deren Status nachverfolgen
   - Entschuldigung bzw. Bestätigung abbilden, falls die EduPage-Rolle dies
     erlaubt
2. **Vertretungen und kurzfristige Planänderungen**
   - Vertretungsplan und Änderungen an Stunde, Raum oder Lehrkraft anzeigen
   - Änderungen im persönlichen Tagesplan sichtbar machen
3. **Tests, Prüfungen und angekündigte Termine**
   - Tests und Prüfungen als eigene, filterbare Termine darstellen
   - Mit dem Kalender und vorhandenen Hausaufgaben verknüpfen
4. **Schulkalender und Veranstaltungen**
   - Schultermine, Ausflüge, schulfreie Tage und relevante Ereignisse anzeigen

### Priorität 2 — Weitere häufige Eltern-/Schülerabläufe

5. **Essensverwaltung**
   - Essen bestellen/abwählen und Menüvarianten wählen, sofern von der Schule
     aktiviert und über die Integration verfügbar
   - Bestellstatus und gegebenenfalls Allergene/Nährwerte anzeigen
6. **Zahlungen und Gebühren**
   - Gebühren, offene und verbuchte Zahlungen sowie Zahlungsinformationen
     anzeigen
   - Zahlungsaktionen nur ergänzen, wenn die offizielle Integration und
     Berechtigungen dies verlässlich unterstützen
7. **Umfragen, Anmeldungen und Bestätigungen**
   - Schulumfragen beantworten
   - Für Aktivitäten, Termine oder Angebote anmelden bzw. Teilnahme bestätigen
8. **Schulnachrichten und Medien**
   - Veröffentlichte Schulnachrichten und Fotogalerien anzeigen, falls diese
     nicht bereits vollständig über die Nachrichten abgedeckt sind

### Priorität 3 — Nur bei ausdrücklicher Erweiterung des Projektziels

Diese Funktionen gehören überwiegend zu Lehrkräften, Schulleitung oder
Verwaltung und sind keine bloßen Ergänzungen der aktuellen Schüler-App:

- digitales Klassenbuch: Unterrichtsstoff, Anwesenheit erfassen, Noten eintragen
- Unterrichts- und Lehrpläne sowie Kurs-/Gruppenverwaltung
- Vertretungsplanung und Ressourcen-/Raumverwaltung
- Zahlungspläne, Zahlungseingänge und Verwaltungsberichte
- Benutzer-, Rollen- und Schulverwaltung
- Schulwebsite bearbeiten, Berichte und weitere Verwaltungswerkzeuge

Vor Arbeiten daran muss der Projektumfang ausdrücklich um Rollen- und
Verwaltungsfunktionen erweitert werden. Die aktuelle Vorgabe ist ein lokales
Einbenutzer-Werkzeug ohne Mehrbenutzerbetrieb.

## Empfohlene Reihenfolge

1. **Machbarkeit prüfen:** Für Anwesenheit, Vertretung, Prüfungen und Kalender
   die vorhandenen Datenquellen und sicheren Offline-Fixtures untersuchen. Keine
   echten Zugangsdaten in Tests oder Repository verwenden.
2. **Lesende Funktionen planen:** zuerst Datenmodelle, API-Verfügbarkeit und
   Web-/App-Parität für Vertretungen, Termine und Anwesenheit klären.
3. **Kernansichten ergänzen:** vorhandene Stundenplan-/Übersichtsflächen um
   Vertretungen, Kalender und Testtermine erweitern; Anwesenheit als eigenen
   Bereich ergänzen, wenn Daten verfügbar sind.
4. **Schreibabläufe separat bewerten:** Krankmeldung, Essenbestellung,
   Umfragen und Anmeldungen brauchen verlässliche EduPage-Schreiboperationen,
   Rollenrechte und nachvollziehbare Fehlerbehandlung.
5. **Zahlungen danach prüfen:** zunächst nur lesende Übersicht; keine
   Zahlungsabwicklung ohne geeignete offizielle Schnittstelle und klare
   Berechtigungs-/Sicherheitsgrundlage.
6. **Rollen-/Adminumfang separat entscheiden:** nicht in den eingefrorenen
   API-Umfang hineinbauen. Falls beauftragt, zuerst neuen Architektur- und
   Sicherheitsplan erstellen.

## Projektgrenzen und Abnahme

- Der bestehende `/api/v1`-Umfang ist laut `BACKEND.md` eingefroren. Neue
  Bereiche benötigen daher einen ausdrücklich aktualisierten API-Plan, bevor
  Implementierung beginnt.
- Keine Secrets, Cache-Dateien oder Login-Daten öffnen oder in Tests verwenden.
- Keine Push-Benachrichtigungen, Datei-Uploads, Mehrbenutzerverwaltung oder
  öffentlicher Produktivbetrieb ohne gesonderten Auftrag.
- Android, macOS und Web bleiben vor iOS priorisiert; iOS bleibt zurückgestellt.
- Pro freigegebenem Bereich braucht es Offline-Tests mit Fixtures/Fakes und
  eine dokumentierte Prüfung der API-/Web-Parität.

## Quellen zum EduPage-Funktionsumfang

- [EduPage — Produktübersicht](https://www.edupage.org/): integrierte
  Schulplattform, Stundenplan, Vertretungen und Schulwebsite.
- [EduPage-App](https://mobile.edupage.org/): Funktionen für Eltern und Schüler,
  darunter Noten, Anwesenheit, Krankmeldungen, Tests/Prüfungen, Unterrichtsstoff,
  Stundenplan, Vertretungen, Essen und Umfragen.
- [EduPage-Hilfe — Klassenbuch](https://help.edupage.org/index.php?id=868):
  Unterrichtsstoff, Anwesenheit, Hausaufgaben und Kalender im Klassenbuch.
- [EduPage-Hilfe — Zahlungen](https://help.edupage.org/?id=e1019&lang_id=14):
  Gebühren-/Zahlungsübersichten und Zahlungsverwaltung.
- [EduPage-Hilfe — Themenübersicht](https://help.edupage.org/?lang_id=20):
  weitere Bereiche wie Kalender, Anmeldungen/Umfragen, Zahlungen und Mensa.
