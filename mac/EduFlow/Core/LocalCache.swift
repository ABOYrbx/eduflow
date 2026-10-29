import Foundation

/// Letzte erfolgreiche Antwort, mit Zeitstempel.
///
/// `savedAt` sagt der Ansicht, **wie alt** die gezeigten Daten sind —
/// das ist der ehrliche Weg, offline sichtbar zu bleiben: nicht so tun,
/// als wäre alles frisch.
public struct CachedPayload: Sendable {
    public let data: Data
    /// Wann die Antwort **vom Server** kam — `nil` bei frischen Daten.
    /// Der Cache setzt hier den Zeitpunkt des Schreibens.
    public let savedAt: Date?

    public init(data: Data, savedAt: Date?) {
        self.data = data
        self.savedAt = savedAt
    }

    /// Kommt der Inhalt aus dem lokalen Cache?
    public var isFromCache: Bool { savedAt != nil }
}

/// Lokale Ablage der letzten Serverantworten (Paket 0, neben dem Token).
///
/// **Warum:** Startet das Backend neu, sind die Bearer-Token ungültig
/// (frischer JWT-Schlüssel oder leere `ApiToken`-Tabelle) und die App
/// würde ohne diesen Cache sofort zum Login springen und alle Daten
/// verlieren. Mit Cache liefert die App stattdessen die zuletzt
/// gesehene Antwort aus und meldet den Stand.
///
/// **Was gespeichert wird:** ausschließlich rohe JSON-Antworten von
/// `GET`-Routen. Niemals der Token (der liegt separat in `TokenStore`),
/// nie ein Geheimnis, nie ein Passwort. Ablage wie der Token: Datei im
/// Application-Support-Container mit `0600`, Verzeichnis `0700` — kein
/// Keychain-Dialog bei Ad-hoc-Signierung.
public final class LocalCache: @unchecked Sendable {
    public static let shared = LocalCache()

    private let fileExtension = "json"
    private let lock = NSLock()
    /// Ablageort. `nil` bedeutet: Application Support wie der Token.
    /// Für Tests wird ein temporäres Verzeichnis gesetzt, damit die
    /// Testläufe weder den echten Cache anfassen noch sich gegenseitig
    /// beeinflussen.
    private let override: URL?

    public init(directory: URL? = nil) {
        override = directory
    }

    /// Für Tests: eigener Ablageort.
    public static func isolated(_ directory: URL) -> LocalCache {
        LocalCache(directory: directory)
    }

    // MARK: - Ablageort

    /// `…/Application Support/de.eduflow.EduFlow/cache`, analog zum Token.
    private func directoryURL() -> URL? {
        let directory: URL
        if let override {
            directory = override
        } else {
            guard let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else { return nil }
            directory = base
                .appendingPathComponent("de.eduflow.EduFlow", isDirectory: true)
                .appendingPathComponent("cache", isDirectory: true)
        }
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )) != nil else { return nil }
        return directory
    }

    /// Routenname → Dateiname. Erlaubt sind Buchstaben, Ziffern, `-`, `_`
    /// und `.`; alles andere wird zu `_`. Der Pfad kann den Cache also
    /// nicht verlassen (Query-Strings wandern in den Schlüssel, nicht in
    /// den Dateinamen).
    private func fileURL(for key: String) -> URL? {
        guard let directory = directoryURL() else { return nil }
        let safe = key.map { character -> Character in
            character.isLetter || character.isNumber || "-_.".contains(character)
                ? character
                : "_"
        }
        return directory.appendingPathComponent(String(safe) + "." + fileExtension)
    }

    // MARK: - Schreiben und Lesen

    /// Antwort sichern. Fehler sind Absicht (z.B. kein Schreibrecht):
    /// der Cache ist eine Bequemlichkeit, sein Ausfall darf die App nie
    /// behindern.
    public func store(_ data: Data, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL(for: key) else { return }
        let envelope = Envelope(savedAt: Date().timeIntervalSince1970, payload: data.base64EncodedString())
        guard let encoded = try? JSONEncoder().encode(envelope) else { return }
        try? Data(encoded).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    /// Letzte Antwort lesen, nil wenn keine da ist.
    public func load(_ key: String) -> CachedPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL(for: key),
            let raw = try? Data(contentsOf: url),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: raw),
            let payload = Data(base64Encoded: envelope.payload)
        else { return nil }
        return CachedPayload(data: payload, savedAt: Date(timeIntervalSince1970: envelope.savedAt))
    }

    /// Cache leeren (Einstellungen → „Cache leeren"). Meldet die Anzahl
    /// der entfernten Einträge; ein Fehler zählt als 0.
    @discardableResult
    public func clear() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let directory = directoryURL(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        var removed = 0
        for name in names where name.hasSuffix("." + fileExtension) {
            let url = directory.appendingPathComponent(name)
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    /// Anzahl der gespeicherten Antworten (für die Anzeige in den
    /// Einstellungen).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let directory = directoryURL(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        return names.filter { $0.hasSuffix("." + fileExtension) }.count
    }

    /// Hülle: Zeitstempel plus Base64, damit binäre Antworten (Dateien)
    /// verlustfrei im JSON liegen.
    private struct Envelope: Codable {
        var savedAt: Double
        var payload: String
    }
}