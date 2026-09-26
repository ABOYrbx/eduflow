# Funktionsübersicht

EduFlow richtet sich derzeit an **eine Schüler-/Eltern-Sitzung**. Die folgenden Funktionen sind im Python-Web/API-Pfad umgesetzt; Android und macOS decken die jeweils genannten Bereiche als Clients ab. Der TypeScript-Pfad zeigt denselben Umfang mit synthetischen Demodaten, nicht mit echten EduPage-Daten.

## Anmeldung, Zwei-Faktor und Geräte

- Anmeldung mit EduPage-Benutzername, Passwort und optionaler Schul-Subdomain; eine Subdomain kann auch aus URL-/Domain-Eingaben normalisiert werden.
- Falls EduPage 2FA verlangt, wird eine kurzlebige Zwischenanmeldung erstellt. Codeabschluss tauscht diese gegen eine normale EduFlow-API-Sitzung.
- Bei falschen Zugangsdaten, Captcha-Anforderung, erneut verlangter 2FA, abgelaufenem Token oder Upstream-Problemen gibt es getrennte API-Fehlercodes.
- Abmeldung widerruft das verwendete API-Token und beendet die jeweilige lokale App-/Web-Sitzung.
- Die Web-Einstellungsseite kann zusätzliche API-Tokens für Clients erstellen und widerrufen. Ein neu erstellter Token wird nur einmal im Klartext angezeigt. Aktive Geräte lassen sich auflisten und einzeln abmelden.
- Token-Refresh ist Rotation: Beim API-Endpunkt wird ein neues Token ausgegeben, das alte widerrufen; gespeicherte EduPage-Zugangsdaten werden zuvor erneut geprüft.

## Übersicht

Die Übersicht ist die Startseite und bündelt:

- laufende Uhr und Datum;
- aktuelle oder nächste nicht entfallene Unterrichtsstunde;
- ungelesene Nachrichten mit lokalem Gelesen-Status;
- offene Hausaufgaben mit Gesamtzählern;
- Wetter, sofern für die Übersicht aktiviert und ein Ort konfiguriert ist;
- Wochen-Essensplan mit Tagesnavigation von Montag bis Freitag.

Die Bereiche, deren Reihenfolge und die angezeigten Nachrichten-/Aufgabenzahlen sind einstellbar. Der Gelesen-Status ist lokal, da die EduPage-Timeline keinen passenden Ungelesen-Status liefert.

## Nachrichten und Unterhaltungen

- Die Nachrichtenliste verarbeitet die Typen `sprava`, `news`, `anketa`, `chat` und `genotif`; Antworten werden in der Liste nicht als neue Top-Level-Nachrichten wiederholt.
- Suche unterstützt mehrere Wörter und ignoriert Unterschiede bei Akzenten/Umlauten. Filter für Nachrichtentyp und Zeitraum sowie Paginierung und Aktualisierung stehen bereit.
- Der Nachrichtenthread zeigt Reaktionen/„Likes“, Antworten und Zusammenfassung. Eine Antwort geht an den bestehenden Thread.
- Neue Nachrichten können an Lehrer und Mitschüler gesendet werden. Empfänger werden gesucht und vor dem Senden serverseitig validiert.
- Anhänge werden durch EduFlow als authentifizierter Proxy geladen. Bevorzugt wird ein kurzlebiges, auf die jeweilige Datei begrenztes `dl`-Token verwendet.
- Das Öffnen der Nachrichtenliste und „Alle gelesen“ pflegen den lokal gespeicherten Gelesen-Status.

## Hausaufgaben, Tests und Prüfungen

- Hausaufgaben kommen aus Timeline-Ereignissen des Typs `homework`. Je nach Einstellung können Prüfungs-/Testtypen mit einbezogen werden.
- Filter: Alle, Offen, Überfällig, Erledigt und Papierkorb; Suche und Zeitraumfilter; Zähler für offene, überfällige, erledigte und ausgeblendete Einträge.
- Sortierung stellt überfällige Aufgaben nach oben, erledigte darunter und Papierkorb-Einträge ans Ende.
- „Erledigt“/„Wieder öffnen“ ändert das Done-Flag über EduPage und pflegt den lokalen Cache unmittelbar nach.
- Der Papierkorb blendet Ereignisse **nur lokal** aus. Er löscht nichts bei EduPage. Wiederherstellen setzt eine echte Hausaufgabe auf „offen“; andere Prüfungsereignisse kennen kein entsprechendes EduPage-Done-Flag.

## Stundenplan und Schulalltag

- Tagesansicht mit Tagesnavigation und Wochenansicht Montag bis Freitag.
- Stunden enthalten Uhrzeit, Fach, Lehrkräfte, Raum und Kennzeichen für Entfall, Online-Unterricht oder Veranstaltung.
- Aufeinanderfolgende Lernzeit-Stunden werden wie im Web als zusammenhängender Block dargestellt. Ganztägige Events erscheinen nicht als reguläre Unterrichtsstunden.
- Schulalltag ergänzt Kalender-/Schulereignisse, Prüfungen, Anwesenheitsmeldungen und Vertretungen.
- Der Vertretungsplan ist wochenweise blätterbar und zeigt Klasse, Stunde, Änderung und Status (neu, geändert, entfällt).
- Die Termindaten sind lesend. Abwesenheiten/Krankmeldungen einreichen oder entschuldigen ist **nicht** umgesetzt.

## Noten

- Anzeigeeinträge werden nach Fach gruppiert, nach Datum sortiert und nach Schulhalbjahr gruppiert.
- Halbjahr: September bis Januar = erstes Halbjahr, Februar bis August = zweites Halbjahr. Fächer erhalten einen gewichteten Schnitt über klassische Noten; verbale/Punkte-/Prozentwerte sind nicht Teil des Notenschnitts.
- Zusätzliche Angaben können Lehrer, Kommentar, Gewichtung, Klassenschnitt, Prozent/Punkte und Datum umfassen.
- Noten bleiben EduPage-Daten. Die App ändert sie nicht.

## Essen und Wetter

### Essen

`essen.py` sucht die Mensa-PDFs für die aktuelle ISO-Kalenderwoche, extrahiert Gerichte und Preise für Montag bis Freitag und cached die strukturierte Woche. Der Wochenplan ist eine Anzeige; Bestellen/Abbestellen von Mahlzeiten ist nicht möglich. Offline wird ein vorhandener Cache genutzt, andernfalls gibt es einen Upstream-Fehler.

### Wetter

Der Python-Pfad bezieht aktuelle Wetterdaten und Vorhersagen über OpenWeatherMap. Ort kommt von Koordinaten oder Stadtname. Die Einstellungsseite kann einen Ort suchen und speichern; der API-Schlüssel bleibt auf dem Server. Ohne Schlüssel ist Wetter nicht verfügbar. Der TypeScript-Fake-Provider liefert stattdessen synthetische Wetterdaten und ist kein Live-Wetterdienst.

## Einstellungen und Darstellung

Accountübergreifend zwischen Web und API gespeicherte Einstellungen:

- Startseite nach Anmeldung;
- Hausaufgaben-Standardfilter und Einbeziehung von Tests;
- maximale Anzahl von Nachrichten und Hausaufgaben auf der Übersicht;
- Reihenfolge der Übersichtsbereiche;
- Wetterkarte aktivieren und Wetter-Stadt festlegen.

Hell/Dunkel/System, Akzentfarbe und „Neue Nachrichten“ sind auf den Clients lokale Darstellungs-/UI-Einstellungen; der Benachrichtigungsschalter ist **kein Push-Dienst**. Android und macOS bieten außerdem Serveradresse, Geräteliste und Cache-Leeren. Die Web-Einstellungsseite verwaltet zusätzlich API-Token.

„Cache leeren“ entfernt die betreffenden lokalen Daten-Caches, aber behält Einstellungen. Danach werden Daten beim nächsten Abruf neu geladen.

## Bewusste Grenzen / nicht umgesetzt

- Keine Datei-Uploads aus den Apps.
- Kein Push-Versand; der Schalter „Neue Nachrichten“ ist nur lokale Präferenz.
- Kein Essen bestellen, Zahlungen ausführen, Umfragen absenden oder Krankmeldungen einreichen.
- Keine Mehrbenutzer-/Schulverwaltung, Lehrer- oder Adminfunktionen.
- Kein öffentlicher Produktivbetrieb.
- iOS ist gebaut, aber laut `AGENTS.md` vorerst zurückgestellt.
- Der TypeScript-Migrationsserver ist kein echter EduPage-Adapter. Siehe [Migration](MIGRATION.md).

Eine ausführliche Liste weiterer geprüfter EduPage-Lücken und möglicher Prioritäten liegt im Funktionslückenplan `plaene/EDUPAGE_LUECKENPLAN.md` (repo-intern, nicht Teil dieser Website).
