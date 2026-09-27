import Combine
import Foundation

// MARK: - Sitzungsablage (Paket 0)
//
// Einzige Stelle für Speichern/Lesen/Löschen der Sitzung + Basis-URL
// (UserDefaults, wie Android DataStore — lokales Werkzeug, kein
// Produktiv-Betrieb). Der Token erscheint nie in UI oder Logs.

@MainActor
final class TokenStore: ObservableObject {
    /// Default: Simulator teilt sich das Mac-Netz (kein 10.0.2.2 nötig).
    static let defaultBaseURL = "http://127.0.0.1:3000/api/v1/"

    @Published private(set) var token = ""
    @Published private(set) var expires = ""
    @Published private(set) var subdomain = ""
    @Published private(set) var username = ""
    @Published private(set) var baseURL = defaultBaseURL
    /// Erscheinungsbild: "system" (Standard), "light", "dark" (Paket F).
    @Published private(set) var appearance = "system"
    /// „Neue Nachrichten"-Schalter (Paket F, lokal — Push ist Nicht-Ziel).
    @Published private(set) var notificationsEnabled = true
    /// Akzent-Schlüssel wie im Web (theme.js data-accent, Standard black).
    @Published private(set) var accent = "black"

    var isLoggedIn: Bool { !token.isEmpty }

    private enum Keys {
        static let token = "eduflow.token"
        static let expires = "eduflow.expires"
        static let subdomain = "eduflow.subdomain"
        static let username = "eduflow.username"
        static let baseURL = "eduflow.baseURL"
        static let appearance = "eduflow.appearance"
        static let notifications = "eduflow.notifications"
        static let accent = "eduflow.accent"
    }

    init() {
        let d = UserDefaults.standard
        token = d.string(forKey: Keys.token) ?? ""
        expires = d.string(forKey: Keys.expires) ?? ""
        subdomain = d.string(forKey: Keys.subdomain) ?? ""
        username = d.string(forKey: Keys.username) ?? ""
        baseURL = d.string(forKey: Keys.baseURL) ?? Self.defaultBaseURL
        let app = d.string(forKey: Keys.appearance) ?? "system"
        appearance = ["light", "dark"].contains(app) ? app : "system"
        notificationsEnabled = d.object(forKey: Keys.notifications) as? Bool ?? true
        accent = (d.string(forKey: Keys.accent) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if accent.isEmpty || !AccentOptions.keys.contains(accent) { accent = "black" }
    }

    func save(token: String, expires: String, subdomain: String, username: String) {
        let d = UserDefaults.standard
        d.set(token, forKey: Keys.token)
        d.set(expires, forKey: Keys.expires)
        d.set(subdomain, forKey: Keys.subdomain)
        d.set(username, forKey: Keys.username)
        self.token = token
        self.expires = expires
        self.subdomain = subdomain
        self.username = username
    }

    func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Keys.token)
        d.removeObject(forKey: Keys.expires)
        d.removeObject(forKey: Keys.subdomain)
        d.removeObject(forKey: Keys.username)
        token = ""
        expires = ""
        subdomain = ""
        username = ""
    }

    func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        UserDefaults.standard.set(normalized, forKey: Keys.baseURL)
        baseURL = normalized
    }

    func setAppearance(_ value: String) {
        let v = ["light", "dark"].contains(value) ? value : "system"
        UserDefaults.standard.set(v, forKey: Keys.appearance)
        appearance = v
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.notifications)
        notificationsEnabled = enabled
    }

    func setAccent(_ key: String) {
        let v = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let valid = AccentOptions.keys.contains(v) ? v : "black"
        UserDefaults.standard.set(valid, forKey: Keys.accent)
        accent = valid
    }

    /// Synchroner Zugriff für den Netzwerk-Layer (thread-sicher).
    nonisolated func currentToken() -> String? {
        let t = UserDefaults.standard.string(forKey: Keys.token) ?? ""
        return t.isEmpty ? nil : t
    }
}
