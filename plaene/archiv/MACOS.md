# EduFlow macOS-App — Bauplan (Mehr-Agenten-fähig)

Ziel: eine native macOS-App (Swift + SwiftUI) gegen das versionierte
JSON-Backend `/api/v1` (siehe `BACKEND.md`, Quelle: `GET /api/v1/openapi.json`).
Das Backend und die Web-Seiten bleiben unverändert und voll funktionsfähig;
die App ist ein reiner API-Client ohne eigene Server-Logik.
Baum: `mac/EduFlow.xcodeproj` + `mac/EduFlow/` Quellen (Plan-Datei hier).

Voraussetzungen: macOS 14+ SDK, Xcode 16+ (`xcodebuild` CLI),
Swift 5 language mode. Der Server läuft auf demselben Mac, daher ist kein
Emulator-Loopback nötig (anders als Android mit `10.0.2.2`).

## 1. Fixe Architektur-Entscheidungen (gelten für alle Pakete)

- Stack fix: Swift 5 language mode, SwiftUI mit App-Lifecycle, macOS 14 als
  Mindestversion, Navigation per Split-Ansicht mit Sidebar (macOS-Idiom
  statt Bottom-Navigation), Netzwerk per URLSession mit async und await,
  JSON-Dekodierung mit automatischer Umwandlung von Schlangen-Schreibweise
  in Camel-Schreibweise, Tests mit Swift Testing und einem stubbenden
  URL-Protokoll pro Route im Offline-Betrieb. Keine externen Abhängigkeiten
  (die System-Frameworks reichen aus; neue Abhängigkeiten sind zu begründen).
- Genau ein Einstieg: die App-Datei plus die Inhaltsansicht plus eine
  zentrale Routenaufzählung. Navigation über die Sidebar: Übersicht,
  Nachrichten, Hausaufgaben, Stundenplan, Noten (Essen und Wetter leben in
  der Übersicht, Einstellungen in der Toolbar beziehungsweise im Sheet).
- MVVM pro Feature: eine Ansicht (dumm, nur Darstellung) plus ein
  Beobachtungsobjekt als ViewModel (Haupt-Thread, beobachtbar) plus ein
  Repository für Datenzugriff. Keine UI-Logik im Data-Layer, keine
  Netzwerk-Logik in den Ansichten. Datenobjekte sind nebenläufig sicher.
- Netzwerk ausschließlich über einen einzigen API-Client und einen einzigen
  Token-Speicher (Token in einer Datei mit Nur-Besitzer-Rechten im
  Application-Support-Verzeichnis, Basis-URL in den UserDefaults).
  Abweichung zum ursprünglichen Keychain-Plan: Bei Ad-hoc-Signierung
  ändert jeder Build die Signatur, sodass macOS bei jedem Start einen
  Schlüsselbund-Dialog zeigen würde — die Datei löst keinen Dialog aus.
  Der Bearer-Token wird zentral in einer einzigen Request-Baustelle
  angehängt; Ausnahme: Datei-Downloads hängen zusätzlich den Token als
  Query-Parameter an (prozentkodiert, wie das Backend erlaubt).
- Basis-URL in den Einstellungen änderbar, Default ist die lokale Adresse
  mit Port 8000 und Pfadpräfix der API-Version 1. Klartext nur für lokalen
  Loopback (Ausnahme in der Info-Datei), sonst nur verschlüsselt. Sandbox
  ist an, mit Entitlement für ausgehende Netzwerkverbindungen.
- Datenobjekte eins zu eins aus den Web-Bauern in `app.py` und `essen.py`
  (Nachrichten, Hausaufgaben, Stunden, Noten, Essensplan, Wetter, Threads,
  Empfänger) — keine eigenen Serializer-Formate. Unbekannte Felder werden
  ignoriert (Standardverhalten der Dekodierung), das garantiert Web- und
  App-Parität. Kennnummern als ganze Zahlen (64-bit); Ausnahme Noten-ID:
  Zahl oder Zeichenkette (flexibler Decoder, vergleiche Rohwert in
  `grade_to_dict`).
- Fehler-Mapping eins zu eins aus `api/core.py` (dortiges Fehler-Vokabular):
  ungültiger oder abgelaufener Token führt zum Login, erneute
  Zwei-Faktor-Pflicht führt zur Neuanmeldung, dazu falsche Zugangsdaten,
  Captcha-Pflicht (Hinweis: einmal im Browser anmelden), Validierungsfehler,
  nicht gefunden, Rate-Limit, fehlende Server-Konfiguration und
  Upstream-Fehler. Deutsche Kurztexte, keine Secrets, Stacktraces oder
  Token in UI oder Logs (kein URL- oder Body-Logging — Downloads tragen
  den Token in der URL).
- Jede Liste ist paginierbar (Limit Standard 50, Maximum 200, Offset ab
  null) mit Pull-to-Refresh (Aktualisierungs-Schalter). Filter heißen wie
  die Web-Parameter (Zeitraum, Typ, Suche, Status, Test-Einbeziehung, Tag).
- Design wie das Web (`static/uber.css`): hell und dunkel nach System,
  acht Akzentfarben, Pillen-Knöpfe. Alle Strings deutsch.
- Übernommene Leitentscheidungen aus dem Android-Pass (gleiche Fallen):
  keine blockierenden Aufrufe auf dem Haupt-Thread (async und await, nie
  auf Sperren warten); der Thread-Bildschirm bekommt die Nachricht als
  Navigationswert mit (kein geteiltes ViewModel, kein Doppel-Request);
  Zwei-Faktor-Navigation nur einmalig (Zustand nach Navigation verbrauchen,
  sonst Zurück-Schleife); Einstellungsfehler nie als Sackgasse (Abmelden
  plus Server-URL immer erreichbar); Gesamtzähler nie aus Listengröße
  ableiten (Server-Zahl verwenden).
- Keine Backend-Änderungen, keine neuen Backend-Dependencies.

## 2. Paket 0 — Kernmodul (ZUERST BAUEN, DANN EINFRIEREN)

Ziel des Pakets: lauffähiges App-Gerüst mit eingefrorener Schnittstelle,
gegen die alle weiteren Pakete programmieren. Danach sind alle Pakete A
bis D parallel baubar.

Module und Dateien: das handgeschriebene minimale Xcode-Projekt
(Einsatzversion macOS 14, Swift 5, Bundle-Kennung des Projekts,
Info-Datei, Entitlements, Debug- und Release-Konfiguration), ein
geteiltes Schema, die App-Datei, die Inhaltsansicht als Sidebar-Rahmen,
die Info-Datei mit Loopback-Ausnahme, die Entitlements-Datei mit Sandbox
und Netzwerk-Client-Recht, dazu der Kern (API-Client, Token-Speicher,
Fehlerabbildung), die gemeinsamen Datenobjekte (Seitendaten, Fehlerkörper,
Fehlercodes), die Routenaufzählung, das Theme (Akzent und Dark Mode) und
die gemeinsamen Ansichten (Pillen-Knopf, Lade-, Fehler- und Leerzustand).

Verhalten im Detail:

1. Der API-Client deckt alle Routen der API-Version 1 aus der
   OpenAPI-Beschreibung ab (Anmeldung, Zwei-Faktor, Abmelden,
   Token-Erneuerung, eigener Benutzer, Geräte, Einstellungen,
   Cache-Leeren, Gesundheit, Nachrichten, Hausaufgaben, Stundenplan,
   Noten, Essen, Wetter). Ressourcen-Inhalte der Pakete B bis D bleiben
   rohe Web-Daten; typisierte Objekte baut jedes Paket selbst.
2. Pfade ohne Token sind Gesundheit, OpenAPI-Beschreibung, Anmeldung und
   Zwei-Faktor-Abschluss. Alle anderen Pfade erhalten den Bearer-Token.
3. Der Token-Speicher ist die einzige Sitzungsablage (Keychain plus
   UserDefaults, beobachtbar): Speichern von Token, Ablauf, Subdomain und
   Benutzername; Leeren; Setzen der Basis-URL; Abfrage, ob eingeloggt;
   Standard-Basis-URL. Der Token erscheint nie in UI oder Logs.
4. Fehler werden aus Meldung plus stabilem Code plus HTTP-Status gebaut,
   mit deutschen Rückfalltexten pro Code.
5. Die Routenaufzählung enthält alle Ziele: Anmeldung, Zwei-Faktor mit
   Zwischen-Token, Übersicht, Nachrichten, Thread mit Nachricht,
   Verfassen, Hausaufgaben, Stundenplan, Noten, Einstellungen, Geräte.
6. Die einzige Split-Ansicht wählt das Startziel aus der Sitzung (ohne
   Token zur Anmeldung, mit Token zur Übersicht beziehungsweise zur
   eingestellten Startseite) und enthält Platzhalter-Ansichten für noch
   offene Pakete (diese werden beim Zusammenführen ersetzt).

Abnahme: Das Projekt baut per Build-Werkzeug fehlerfrei; Anmeldeansicht
erscheint ohne Sitzung; Gesundheitsroute antwortet gegen den lokalen
Server;.health check; kein Token in Logs.

## 3. Paket A — Authentifizierung, Einstellungen und Geräte

Ziel des Pakets: Anmelden inklusive Zwei-Faktor-Ablauf, Abmelden,
Sitzungsverwaltung, Einstellungen und Geräteverwaltung. Nur gegen das
Paket-0-Interface, keine Kern-Signaturen ändern.

Module und Dateien: Datenobjekte für Anmeldung und Einstellungen,
Repositories für Auth und Einstellungen, ViewModel plus Anmelde- und
Zwei-Faktor-Ansicht, ViewModel plus Einstellungs- und Geräteansicht.

Verhalten im Detail:

1. Anmeldung mit Benutzername (Pflicht), Passwort (Pflicht), optionaler
   Schuldomain und Gerätename (zum Beispiel lokaler Rechnername).
   Clientseitige Validierung fehlender Felder meldet einen
   Validierungsfehler ohne Netzaufruf.
2. Antwort mit Status ok liefert Token, Ablauf, Subdomain und Benutzername
   und speichert die Sitzung. Antwort mit Zwei-Faktor-Pflicht liefert ein
   Zwischen-Token plus Hinweismeldung und navigiert genau einmal zur
   Code-Eingabe; der Anmeldezustand wird dabei verbraucht, damit die
   Zurück-Navigation keine Schleife baut.
3. Zwei-Faktor-Abschluss mit Zwischen-Token und Code tauscht gegen ein
   vollwertiges Token. Falscher Code meldet ungültigen Code, unbekanntes
   oder abgelaufenes Zwischen-Token meldet ungültigen Zwischenschritt.
   Leerer Code wird clientseitig abgefangen.
4. Abmelden widerruft serverseitig nach bestem Bemühen und leert den lokalen
   Speicher in jedem Fall. Token-Erneuerung rotiert die Sitzung.
5. Eigener Benutzer liefert Subdomain und Benutzername des Token-Inhabers.
   Geräteliste zeigt eigene Tokens ohne Secrets (Kennung, Kurzform,
   Gerätename, Erstellung, Ablauf, neueste zuerst); Entfernen widerruft
   gezielt mit serverseitigem Besitzschutz.
6. Einstellungen lesen liefert Schema und Werte mit Parität zum
   Server-Schema in `app.py` (Startseite mit fünf Zielen,
   Hausaufgaben-Standardfilter mit fünf Stufen, Tests-Schalter,
   zwei Begrenzungen je eins bis fünfzig; ungültige Werte fallen auf
   Defaults). Speichern sendet echte JSON-Booleans und toleriert die
   Antwort ohne Schema. Cache-Leeren meldet die Anzahl und erhält die
   Einstellungen.
7. Abgelaufener oder ungültiger Token mit gespeicherter Sitzung leert den
   Speicher und führt zum Login; dabei kein Server-Abmelden mit totem
   Token (das erzeugte nur zusätzliches Rauschen). Ohne gespeicherte
   Sitzung ist dieselbe Antwort nur ein Fehlertext (kein Eager-Load-Spam
   beim Start). Die Einstellungsansicht lädt beim Öffnen frisch.
8. Server-URL ist auf Anmelde- und Einstellungsansicht änderbar ohne
   Rebuild. Die Einstellungsansicht zeigt im Fehlerfall zusätzlich
   Wiederholen, Server-Übernahme und Abmelden (nie Sackgasse).

Fehler und Sonderfälle: falsche Daten melden falsche Zugangsdaten;
Captcha-Zwang meldet den Browser-Hinweis; zu viele Versuche melden das
Rate-Limit; erneute Zwei-Faktor-Pflicht führt zur Neuanmeldung.

Tests (offline, stubbendes URL-Protokoll, kein echtes Login): Routenform
von Anmeldung und Zwei-Faktor, alle Fehlercodes des Pakets
(Falschdaten, Captcha, Rate-Limit, ungültiger Code, ungültiger
Zwischenschritt, Validierung), Einstellungs-Defaults und -Clamping,
Booleans als echte JSON-Bools, Geräte ohne Secrets, 401-Verhalten mit
und ohne Sitzung.

Abnahme: Anmelden führt über Zwei-Faktor zur Übersicht beziehungsweise
zur eingestellten Startseite; falsche Daten, Captcha-Hinweis und
Rate-Limit erscheinen deutsch; Abmelden widerruft und leert den Speicher;
danach ist der alte Token abgelehnt; Server-URL-Wechsel wirkt ohne Rebuild.

## 4. Paket B — Nachrichten und Threads

Ziel des Pakets: Nachrichtenliste mit Filter und Suche, Thread-Ansicht
mit Likes und Antworten, Verfassen mit Empfängersuche, Gelesen-Markierung
und Anhang-Downloads. Nur gegen Paket-0-Interface, keine Kern-Signaturen
ändern.

Module und Dateien: Nachrichten-Repository, Nachrichten-Datenobjekte,
Listen-, Thread- und Verfassen-Ansicht plus ViewModels.

Verhalten im Detail:

1. Nachrichtenliste nur mit Top-Level-Einträgen (Antworten filtert das
   Backend wie im Web heraus), neueste zuerst. Parameter wie die
   Web-Route: Zeitraum (Standard sehr früh), Typfilter (fünf
   Nachrichtentypen plus Alle als Default), Textsuche über alle Wörter,
   Paginierung und Aktualisierungs-Schalter.
2. Datenobjekte eins zu eins aus dem Web-Bauer `event_to_dict`: Kennung,
   Zeitstempel in Anzeige- und ISO-Form, Sortierschlüssel, Autor,
   Empfänger, Typ mit deutschem Label, Text, Stern- und Erledigt-Kennzeichen,
   Reaktionszähler, Rohdaten und Anhänge mit Name und Adresse.
3. Thread lädt Likes, Antworten und Zusammenfassung aus der bestehenden
   Thread-Logik inklusive Datei-Cache und zeigt den Cache-Hinweis; die
   Antwortliste enthält Name, Datum und Text pro Antwort.
4. Gelesen-Markierung übernimmt die bestehende Gelesen-Logik für alle
   aktuellen Nachrichtentypen und meldet nur den Zähler zurück (der Server
   kennt kein Ungelesen-Kennzeichen, wie im Web über Gesehen-Dateien).
5. Empfängerliste nutzt den bestehenden Helfer (Lehrer plus Mitschüler,
   nach Name sortiert, paginiert). Empfängerkennungen werden clientseitig
   nach dem Server-Muster geprüft (Rollenname plus Zahl,
   Großschreibung egal); die Prüfung folgt dem Empfänger-Regex in `app.py`.
6. Senden und Antworten nutzen die bestehenden Sende-Helfer mit denselben
   Body-Schlüsseln wie das Backend (Empfängerliste plus Text mit
   Längenbegrenzung; Antwort nur Text an alle im Thread). Leere Empfänger
   oder leerer Text melden clientseitig einen Validierungsfehler. Nach dem
   Senden lädt die Liste frisch (das Backend liefert synchron), nach der
   Antwort wird der Thread aufgefrischt.
7. Thread-Route trägt die Nachricht als Navigationswert (Header ohne
   Extraladung, kein Doppel-Request). Anhang-Download läuft als
   authentifizierter Proxy über die eingeloggte Sitzung mit Query-Token
   (native Downloader setzen nicht immer Header), nur EduPage-Adressen,
   Dateiname aus den Nachrichtendaten, fremde Adressen werden geblockt.

Fehler und Sonderfälle: unbekannter Nachrichtentyp meldet Validierung;
falsches Datumsformat meldet Validierung; fehlende Nachricht oder Datei
meldet nicht gefunden; abgelaufene Sitzung führt zum Login.

Tests (offline, stubbendes URL-Protokoll): Routenform aller sieben
Nachrichten-Endpunkte (Parameter- und Body-Schlüssel wie in
`api/messages.py`), Thread mit Likes und Antworten, Senden und Antworten
gegen Stub-Cache, Download verweigert fremde Adressen, Paginierung und
401-Verhalten.

Abnahme: Liste mit Paging, Filter und Suche wie die Web-Seite für
Nachrichten; Thread mit Likes; Senden erscheint sofort; Antworten landen
im Thread; Gelesen-Zähler stimmt; Validierung bei leeren Empfängern und
leerem Text.

## 5. Paket C — Hausaufgaben und Noten

Ziel des Pakets: Hausaufgabenliste mit Statusfiltern, Zählern, Erledigt-
und Papierkorb-Schaltern sowie Notenliste mit Halbjahr-Tabs, Suche und
Schnitt. Nur gegen Paket-0-Interface, keine Kern-Signaturen ändern.

Module und Dateien: Hausaufgaben- und Noten-Repository, Datenobjekte für
beide Bereiche, Listenansichten plus ViewModels.

Verhalten im Detail (Hausaufgaben):

1. Liste mit Zeitraum, Statusfilter (alle, offen, überfällig, erledigt,
   Papierkorb), Test-Einbeziehung, Suche und Paginierung; Antwortobjekte
   aus dem bestehenden Hausaufgaben-Bauer in bestehender Sortierung
   (überfällig zuerst, Papierkorb-Einträge ans Ende), Zähler für offen,
   überfällig, erledigt und Papierkorb werden mitgeliefert.
2. Datenobjekte eins zu eins aus `homework_to_dict` plus lokalem
   Versteckt-Kennzeichen: Kennung, Typ mit Label, Titel, Beschreibung,
   Fach, Autor, Empfänger, Aufgaben- und Fälligkeitsdaten (Anzeige- und
   Rohform), Status mit Stilklassen, Erledigt-Kennzeichen mit Zeitpunkt,
   Stern- und Versteckt-Kennzeichen, Zusatzdaten. Wichtig: Der Zähler-
   Schlüssel für Überfällige ist ascii ohne Umlaut.
3. Offen zählt offene plus heute fällige ohne Papierkorb (wie die
   Web-Zähler). Statuswechsel ist nach erneutem Laden sichtbar.
4. Erledigt-Markierung nutzt den bestehenden Server-Helfer und pflegt den
   lokalen Cache sofort nach (Gesamtzahl bleibt die Server-Zahl). Der
   Papierkorb nutzt dieselbe lokale Dateiablage wie das Web (kein
   Server-Zustand), inklusive der Regel, dass Zurückholen gleichzeitig als
   offen markiert. Auf macOS primär Knöpfe und Kontextmenü, Wischgesten
   optional.

Verhalten im Detail (Noten):

1. Liste liefert Anzeigeobjekte aus dem bestehenden Noten-Bauer in
   Cache-Reihenfolge (keine neuen Filter, keine neue Sortierung) in der
   Listen-Hülle plus Cache-Info. Ist der Cache frisch und kein Refresh
   verlangt, antwortet die Route ohne EduPage-Login.
2. Datenobjekte eins zu eins aus `grade_to_dict`: Kennung (Zahl oder Text),
   Titel, Fach, Lehrer, Datumsanzeige und ISO-Datum, Sortierschlüssel,
   Kommentar, Notenanzeige, Zahlenwert und Gewichtung mit Anzeigen,
   Zusatz (Punkte, Prozent, Gewichtung), Abzeichen, Klassenschnitt mit
   Anzeige und Klassik-Kennzeichen.
3. Gruppierung clientseitig wie die Web-Route für Noten: Halbjahr-Tabs aus
   den geladenen Noten (neuestes zuerst plus Gesamt-Anhang; Schuljahr
   September bis August, September bis Januar erstes, Februar bis August
   zweites Halbjahr; deutsche Halbjahr-Labels), Fächer alphabetisch, Noten
   neueste zuerst, Schnitt als gewichteter Mittelwert über klassische
   Noten im gültigen Bereich mit Gewichtung, auf zwei Stellen gerundet,
   deutsche Dezimalkommas in Anzeigen.

Fehler und Sonderfälle: ungültige Paginierung meldet Validierung;
ungültig gewordene Zugangsdaten melden falsche Zugangsdaten; Captcha-Zwang
und erneute Zwei-Faktor-Pflicht wie im Ressourcen-Muster; alle anderen
EduPage-Fehler melden Upstream.

Tests (offline, stubbendes URL-Protokoll): Routenform aller vier
Endpunkte (Body-Schlüssel für Erledigt und Papierkorb), Filter, Zähler
und Sortierung gegen Stub wie im Web, Statuswechsel sichtbar, Noten-
Schnitt und Halbjahr-Ableitung gegen bekannte Werte, Paginierung und
401-Verhalten.

Abnahme: Filter, Zähler und Sortierung stimmen mit der Web-Seite für
Hausaufgaben überein; Erledigt- und Papierkorb-Schalter wirken sofort und
überdauern Neuladen; Noten-Tabs, Suche und Schnitt stimmen mit der
Web-Seite für Noten überein.

## 6. Paket D — Stundenplan, Übersicht, Essen und Wetter

Ziel des Pakets: Tages- und Wochen-Stundenplan, Startseiten-Übersicht mit
Uhr, Nachrichten, Hausaufgaben, Stunden, Essen und Wetter. Nur gegen
Paket-0-Interface, keine Kern-Signaturen ändern.

Module und Dateien: Stundenplan- und Meta-Repository, Datenobjekte für
Stunden, Essen und Wetter, Tages- und Wochenansicht plus ViewModel,
Übersichtsansicht plus ViewModel.

Verhalten im Detail (Stundenplan):

1. Tagesansicht nimmt ein Tagesdatum (Standard heute) und liefert
   Anzeigeobjekte aus dem bestehenden Stunden-Bauer inklusive
   Zusammenfassung aufeinanderfolgender Lernzeit-Stunden wie im Web
   (Anzeige mehrerer Stunden, mehrzeilige Blöcke). Tag-Navigation mit
   Zurück, Heute und Weiter.
2. Datenobjekte eins zu eins aus `lesson_to_dict`: Stundennummer, Zeitspanne
   (Beginn bis Ende mit Gedankenstrich), Titel, Lernzeit-Kennzeichen,
   Lehrer, Räume, Entfall-, Veranstaltungs- und Online-Kennzeichen plus
   Block-Bezeichnung und Zeilenspannweite aus der Zusammenfassung.
3. Wochenansicht nimmt ein Datum innerhalb der Woche und liefert Montag bis
   Freitag mit denselben Tagesobjekten plus Wochenbezeichnung; ganztägige
   Veranstaltungen werden nicht als Stunden eingetragen (wie im Web).
   Wochen-Navigation in Sieben-Tage-Schritten, Heute springt in die
   aktuelle Woche.
4. Beide nutzen den bestehenden Stundenplan-Cache mit dessen Laufzeiten
   für Vergangenheit, Heute und Zukunft; ein Aktualisierungs-Schalter lädt
   frisch. Tagesantwort mit Tag, deutscher Bezeichnung, Vortag, Folgetag,
   Heute-Datum, Stunden und Cache-Info; Wochenantwort mit Tag, Montag,
   Wochenbezeichnung, Tagesliste und Cache-Info.

Verhalten im Detail (Essen und Wetter):

1. Wochen-Essensplan mit Aktualisierungs-Schalter aus dem bestehenden
   Essensmodul inklusive Wochen-Cache; Fehler melden Upstream. Braucht kein
   EduPage-Login. Antwort mit Woche, Bezeichnung, PDF-Quelle, Tagen von
   Montag bis Freitag (je Datum, Gerichte mit Text und Preis, Hinweis),
   Heute-Tag, Cache-Kennzeichen und Cache-Info. Tages-Blätterer mit
   Zurück und Weiter, Start beim heutigen Tag, PDF-Link.
2. Wetter nutzt denselben Helfer wie die Web-Route (Schlüssel bleibt
   serverseitig). Antwort mit Stadt, Heute-Werten (Temperatur, Maximum,
   Minimum, Beschreibung, Icon, Regenwahrscheinlichkeit), Morgen- und
   Übermorgen-Karte, Stundenvorschau und Details (gefühlte Temperatur,
   Feuchte, Druck, Wind mit Richtung, Wolken, Sichtweite, Sonnenauf- und
   -untergang). Fehlercodes: Validierung ohne Ort, fehlende Konfiguration
   ohne Schlüssel, Upstream bei Upstream- und Netzfehlern. Ort per Stadt
   (Koordinaten optional wie im Backend).

Verhalten im Detail (Übersicht):

1. Startseite nach Anmeldung unter Beachtung der eingestellten Startseite
   (wie Web): Uhr (live, deutsches Format), Wetterkarte, aktuelle und
   nächste Stunde (laufende nicht entfallene Stunde, sonst nächste
   kommende; keine Veranstaltungen; Zeitspanne wie im Web parsen).
2. Neueste Nachrichten im Rahmen der eingestellten Begrenzung,
   Gesamtzahl aus der Liste; offene Hausaufgaben im Rahmen der
   eingestellten Begrenzung (ohne erledigte und versteckte) plus Zähler;
   Essen-heute mit Pager. Wiederverwendet die Listen aus den Paketen B
   und C (keine eigene Server-Logik); Teilergebnisse bleiben sichtbar,
   Fehler werden einzeln gemeldet.
3. Knöpfe zu allen Bereichen (Nachrichten, Hausaufgaben, Stundenplan,
   Noten, Einstellungen).

Fehler und Sonderfälle: ungültiges Tagesdatum meldet Validierung;
Wochenende und freie Tage zeigen Schulfrei statt Fehler; fehlender
Essensplan meldet Upstream mit Cache-Rückfall wie im Backend;
Wetter ohne Ort oder ohne Schlüssel wie oben.

Tests (offline, stubbendes URL-Protokoll): Routenform aller vier
Endpunkte (Tages- und Wochenschlüssel, Essenswoche mit Preisen und Quelle,
Wetter-Payload), Lernzeit-Blöcke und Kennzeichen gegen Stub wie im Web,
Zeit- und Halbjahr-Ableitungen gegen bekannte Werte, aktuelle und nächste
Stunde gegen feste Zeiten, Paginierung wo vorhanden und 401-Verhalten.

Abnahme: Tag und Woche gegen Stub liefern dieselben Strukturen wie die
Web-Seite (Lernzeit-Blöcke, Entfall- und Online-Kennzeichen);
Essensantwort enthält alle fünf Tage mit Preisen und Quelle;
Wetter-Fehlercodes korrekt; Übersicht zeigt Uhr, Nachrichten,
Hausaufgaben, Stunden, Essen und Wetter wie die Web-Übersicht.

## 7. Paketübergreifende Regeln für alle Agenten

- Keine bestehenden Web-Routen, Templates oder Helper-Signaturen ändern.
  Neue Module liegen in eigenen Paketverzeichnissen unter `mac/EduFlow/`;
  die Anbindung an die App erfolgt an genau einer Stelle (Inhaltsansicht
  plus Routenaufzählung).
- Jeder Agent arbeitet auf einem eigenen Zweig ab dem Hauptzweig und fasst
  nur seine Paket-Dateien plus die eine Anbindungsstelle an.
- Projektdatei diszipliniert pflegen: neue Dateien als Dateireferenz plus
  Build-Eintrag in der Paket-Gruppe und der Quellphase eintragen (Muster
  aus Paket 0 kopieren); kein Build ohne Check per Build-Werkzeug.
- Neue Abhängigkeiten sind zu begründen; bevorzugt wird ohne neue
  Abhängigkeiten gebaut (URLSession, Foundation, SwiftUI und Swift Testing
  reichen aus).
- Tests laufen offline gegen Stub-Antworten, niemals mit echten
  Zugangsdaten im Repository. Jedes Paket liefert Tests, die Routenform,
  Fehlercodes, Paginierung und Cache-Wiederverwendung prüfen.
- Antworttexte für Fehler sind deutsch, kurz und ohne interne Details
  (keine Stacktraces, keine Schlüssel, keine Pfade, keine URLs mit Token).

## 8. Integrations-Reihenfolge und Abnahme

1. Paket 0 fertigstellen und Schnittstelle einfrieren (Build grün,
   Anmeldeansicht ohne Sitzung, Gesundheit gegen lokalen Server grün).
2. Pakete A bis D parallel bauen (alle nur gegen die eingefrorene
   Kern-Schnittstelle und die bestehenden Helper).
3. Zusammenführen in dieser Reihenfolge: Auth, Nachrichten, Hausaufgaben,
   Stundenplan, Noten, Essen und Wetter, Einstellungen und Cache
   (Platzhalter in der Inhaltsansicht ersetzen).
4. End-zu-End-Abnahme gegen den lokalen Server (Gesundheit grün):
   Anmelden (inklusive simulierter Zwei-Faktor-Pflicht), jede Liste mit
   Paginierung, je ein Schreibaufruf pro Paket (senden, erledigt,
   Cache leeren), Abmelden mit anschließend abgelehntem Token, sowie der
   Nachweis, dass alle Web-Seiten unverändert rendern (End-zu-End-Test
   des Backends grün für Web-Parität).
5. Nicht-Ziele dieser Ausbaustufe: Push-Benachrichtigungen, Datei-Uploads
   von der App, Mehrbenutzer-Verwaltung, App-Store-Release und
   Notarisierung, eigene App-Icons und ein öffentlicher Betrieb (der Server
   bleibt ein lokales Werkzeug wie bisher).

## Addendum — Schulalltag

`School/SchoolViews.swift` stellt Kalendertermine, Prüfungen,
Anwesenheitsereignisse und Vertretungen dar. Die Vertretungsansicht bietet
Wochen-Navigation und nutzt die additiven Routen `school/agenda` und
`substitutions/week`.
