import Foundation

/// 401-Entscheidung ohne Netz und ohne Speicher-Zugriff (testbar):
/// Mit gespeicherter Sitzung leeren und zum Login, ohne Sitzung nur
/// Fehlertext (kein Eager-Load-Spam beim Start). Mit totem Token nie
/// Server-Abmelden (das erzeugte nur zusätzliches Rauschen).
public enum SessionRecovery {
    public static func forceLogout(error: APIError, isLoggedIn: Bool) -> Bool {
        error.needsReLogin && isLoggedIn
    }
}

/// Ergebnis einer Anmelde-Aktion für die Navigation (wird genau einmal
/// verbraucht — sonst baut die Zurück-Navigation eine Schleife).
public enum LoginAction: Equatable, Sendable {
    case twoFA(pending: String)
    case loggedIn(route: Route)
}

/// Anmelde-Logik (dumm bleibt die Ansicht, Netzwerk bleibt im Repository).
@MainActor
@Observable
public final class LoginViewModel {
    public var username = ""
    public var password = ""
    public var subdomain = ""
    public var device = Host.current().localizedName ?? ""
    public var baseURL: String
    public var isLoading = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
        baseURL = store.baseURLString
    }

    public func applyBaseURL() {
        store.setBaseURL(baseURL)
        baseURL = store.baseURLString
    }

    public func startDemo() async -> LoginAction? {
        store.startDemo()
        username = "demo"
        password = "demo"
        subdomain = "demo"
        return await login()
    }

    public func stopDemo() {
        store.stopDemo()
        clearError()
    }

    /// Fehler zurücksetzen (wird beim Tippen aufgerufen).
    public func clearError() {
        error = nil
    }

    /// Anmelden: ok → Sitzung speichern plus Startseite laden;
    /// Zwei-Faktor-Pflicht → Zwischen-Token für genau eine Navigation.
    public func login() async -> LoginAction? {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let repo = AuthRepository(client: store.makeClient())
        do {
            let result = try await repo.login(
                username: username,
                password: password,
                subdomain: subdomain,
                device: device
            )
            switch result {
            case .twoFaRequired(let pending, _):
                return .twoFA(pending: pending)
            case .loggedIn(let token, let expires, let sub, let user):
                store.save(token: token, expires: expires, subdomain: sub, username: user)
                return .loggedIn(route: await landing())
            }
        } catch let apiError as APIError {
            error = apiError
            return nil
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
            return nil
        }
    }

    /// Eingestellte Startseite laden (best-effort, sonst Übersicht).
    private func landing() async -> Route {
        let repo = SettingsRepository(client: store.makeClient())
        if let (_, values) = try? await repo.load() {
            return values.landingRoute()
        }
        return .overview
    }
}

/// Zwei-Faktor-Logik (Code aus E-Mail oder App).
@MainActor
@Observable
public final class TwoFAViewModel {
    public var code = ""
    public var isLoading = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    /// Fehler zurücksetzen (wird beim Tippen aufgerufen).
    public func clearError() {
        error = nil
    }

    /// Abschluss: ok → Sitzung speichern plus Startseite laden.
    public func submit(pendingToken: String) async -> Route? {
        isLoading = true
        self.error = nil
        defer { isLoading = false }
        let repo = AuthRepository(client: store.makeClient())
        do {
            let result = try await repo.submit2FA(pendingToken: pendingToken, code: code)
            switch result {
            case .loggedIn(let token, let expires, let sub, let user):
                store.save(token: token, expires: expires, subdomain: sub, username: user)
                let settings = SettingsRepository(client: store.makeClient())
                if let (_, values) = try? await settings.load() {
                    return values.landingRoute()
                }
                return .overview
            case .twoFaRequired:
                self.error = APIError(
                    code: ErrorCodes.upstream,
                    message: APIError.germanFallback(for: ErrorCodes.upstream)
                )
                return nil
            }
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
            }
            self.error = apiError
            return nil
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
            return nil
        }
    }
}
