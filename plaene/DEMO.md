# EduFlow-Demomodus

Der Demomodus ist für Vorführungen und Screenshots gedacht. Android und macOS
verbinden sich dafür ausschließlich mit dem lokalen Fake-Backend auf Port
8101. Es zeigt fest eingebaute Beispieldaten und verwendet keine EduPage-
Anmeldedaten. Ist der Demo-Server nicht erreichbar, zeigen die Apps einen
Verbindungsfehler; sie wechseln nicht auf den echten Server.

## Demo starten

1. Das Monorepo einmalig gemäß [Migrationsanleitung](../migration/README.md)
   lokal einrichten.
2. Im Projektordner `./run.sh` starten. Das Skript setzt für die API explizit
   `EDUFLOW_PROVIDER=fake`, startet sie auf Port `8101` und die Weboberfläche
   auf Port `3000`.
3. In der EduFlow-Weboberfläche oder in der Android- bzw. macOS-App
   **Demo ansehen** wählen.

Die Clients nutzen diese festen Adressen:

| Client | Demo-API |
|---|---|
| Android-Emulator | `http://10.0.2.2:8101/api/v1/` |
| macOS | `http://127.0.0.1:8101/api/v1/` |

## Testkonten

- Standard: Benutzername `demo`, Passwort `demo`.
- Zwei-Faktor-Vorführung: Benutzername `demo-2fa`, Passwort `demo`, Code
  `123456`.

Diese Konten funktionieren nur mit dem Fake-Provider. Namen und Inhalte sind
Beispiele, keine echten Schul- oder Personendaten. Änderungen wie das Senden
von Demo-Nachrichten bleiben im Fake-Backend.

## Demo beenden

In Android **Mehr → Abmelden** oder auf dem Login-Bildschirm **Demo
verlassen** wählen. Auf dem Mac **Abmelden** oder auf dem Login-Bildschirm
**Demo verlassen** wählen. Beim Verlassen wird die Demo-Sitzung gelöscht und
die normale lokale Serveradresse wiederhergestellt. Während die Demo aktiv
ist, können die Apps die Serveradresse nicht ändern.

## Abgrenzung

Der Demo-Modus setzt voraus, dass `./run.sh` die API als Fake-Provider auf dem
lokalen Port `8101` gestartet hat. Die nativen Apps rufen in diesem Modus
keinen EduPage-Endpunkt und keinen Wetterdienst direkt auf. Die echten lokalen
Python-App und ihre Sitzungen werden für die Demo nicht verwendet.
