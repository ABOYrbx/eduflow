import Foundation

/// Einzige Sitzungsablage (Paket 0, eingefroren).
///
/// Der Token liegt in einer Datei mit Nur-Besitzer-Rechten (0600) im
/// Application-Support-Verzeichnis — bewusst keine Keychain: Bei
/// Ad-hoc-Signierung ändert jeder Build die Signatur, sodass macOS bei
/// jedem Start einen Schlüsselbund-Dialog („EduFlow möchte auf Ihre
/// vertraulichen Informationen zugreifen") zeigen würde. Die Datei löst
/// keinerlei System-Dialog aus. Basis-URL plus Anzeige-Felder liegen
/// weiter in den UserDefaults. Der Token erscheint nie in UI oder Logs.
///
/// Teilbar über Isolation hinweg: Schreiben passiert auf dem Haupt-Thread
/// (SwiftUI-Konvention für beobachtbare Modelle), Lesen kopiert nur kurze
/// Zeichenketten für den Netzwerk-Client.
@Observable
public final class TokenStore: @unchecked Sendable {
    /// Default aus der Plan-Datei (lokaler Server, kein Emulator-Loopback).
    public static let defaultBaseURL = "http://127.0.0.1:3000/api/v1/"
    public static let demoBaseURL = "http://127.0.0.1:3100/api/v1/"

    private static let defaultsBaseURL = "de.eduflow.baseURL"
    private static let defaultsSubdomain = "de.eduflow.subdomain"
    private static let defaultsUsername = "de.eduflow.username"
    private static let defaultsExpires = "de.eduflow.expires"
    private static let defaultsDemoMode = "de.eduflow.demoMode"
    private static let tokenFileName = "session.token"

    public private(set) var token: String = ""
    public private(set) var baseURLString: String = TokenStore.defaultBaseURL
    public private(set) var subdomain: String = ""
    public private(set) var username: String = ""
    public private(set) var expires: String = ""
    public private(set) var isDemo = false

    public var isLoggedIn: Bool { !token.isEmpty }

    public init() {
        let stored = Self.readToken()
        token = stored
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: Self.defaultsBaseURL) ?? ""
        baseURLString = base.isEmpty ? Self.defaultBaseURL : base
        subdomain = defaults.string(forKey: Self.defaultsSubdomain) ?? ""
        username = defaults.string(forKey: Self.defaultsUsername) ?? ""
        expires = defaults.string(forKey: Self.defaultsExpires) ?? ""
        isDemo = defaults.bool(forKey: Self.defaultsDemoMode)
        if token.isEmpty {
            subdomain = ""
            username = ""
            expires = ""
        }
    }

    public func save(token: String, expires: String, subdomain: String, username: String) {
        Self.writeToken(token)
        self.token = token
        self.expires = expires
        self.subdomain = subdomain
        self.username = username
        let defaults = UserDefaults.standard
        defaults.set(expires, forKey: Self.defaultsExpires)
        defaults.set(subdomain, forKey: Self.defaultsSubdomain)
        defaults.set(username, forKey: Self.defaultsUsername)
    }

    /// Lokalen Speicher immer leeren (gilt auch bei Netz- oder Token-Fehler).
    public func clear() {
        let wasDemo = isDemo
        Self.deleteToken()
        token = ""
        subdomain = ""
        username = ""
        expires = ""
        isDemo = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.defaultsSubdomain)
        defaults.removeObject(forKey: Self.defaultsUsername)
        defaults.removeObject(forKey: Self.defaultsExpires)
        defaults.removeObject(forKey: Self.defaultsDemoMode)
        if wasDemo {
            baseURLString = Self.defaultBaseURL
            defaults.removeObject(forKey: Self.defaultsBaseURL)
        }
    }

    /// Erzwingt für Demo-Sitzungen den lokalen Fake-Server.
    public func startDemo() {
        isDemo = true
        baseURLString = Self.demoBaseURL
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.defaultsDemoMode)
        defaults.set(Self.demoBaseURL, forKey: Self.defaultsBaseURL)
    }

    public func stopDemo() {
        isDemo = false
        baseURLString = Self.defaultBaseURL
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.defaultsDemoMode)
        defaults.removeObject(forKey: Self.defaultsBaseURL)
    }

    public func setBaseURL(_ url: String) {
        if isDemo {
            baseURLString = Self.demoBaseURL
            UserDefaults.standard.set(Self.demoBaseURL, forKey: Self.defaultsBaseURL)
            return
        }
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.isEmpty ? Self.defaultBaseURL : normalized
        baseURLString = value
        UserDefaults.standard.set(value, forKey: Self.defaultsBaseURL)
    }

    /// API-Client mit lebendigen Werten (Token und URL werden pro
    /// Request gelesen, kein Neuaufbau nach Login nötig).
    public func makeClient(session: URLSession? = nil) -> APIClient {
        APIClient(
            baseURL: { [weak self] in self?.baseURLString ?? TokenStore.defaultBaseURL },
            token: { [weak self] in self?.token },
            session: session ?? TokenStore.defaultSession(),
            // Nur die App verdraengt den lokalen Rückfall: Faellt das
            // Backend nach einem Neustart aus, zeigt die App weiter die
            // zuletzt geladenen Daten statt den Login zu erzwingen.
            cache: LocalCache.shared
        )
    }

    public static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    // MARK: - Token-Datei ( privat, nie Token loggen )

    /// Ablageort im Sandbox-Container (ohne Zusatz-Entitlement les- und
    /// schreibbar, löst keinen System-Dialog aus).
    private static func tokenFileURL() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = base.appendingPathComponent("de.eduflow.EduFlow", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        return directory.appendingPathComponent(tokenFileName, isDirectory: false)
    }

    private static func readToken() -> String {
        guard let url = tokenFileURL(),
            let data = try? Data(contentsOf: url),
            let token = String(data: data, encoding: .utf8),
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ""
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeToken(_ token: String) {
        guard let url = tokenFileURL(),
            let data = token.data(using: .utf8)
        else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            return
        }
    }

    private static func deleteToken() {
        guard let url = tokenFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
