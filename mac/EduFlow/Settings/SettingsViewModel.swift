import Foundation

/// Einstellungs-Logik (Paket A): frisch laden beim Öffnen, Fehler nie
/// als Sackgasse (Wiederholen, Server-Übernahme und Abmelden bleiben
/// immer erreichbar).
@MainActor
@Observable
public final class SettingsViewModel {
    public var values = SettingsValues()
    public var baseURL: String
    public var isLoading = false
    public var isSaving = false
    public var isClearing = false
    public var isLoggingOut = false
    public var error: APIError?
    public var clearMessage: String?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
        baseURL = store.baseURLString
    }

    public func applyBaseURL() {
        store.setBaseURL(baseURL)
        baseURL = store.baseURLString
    }

    /// Beim Öffnen frisch laden (ohne Sitzung: nur Fehlertext).
    public func load(onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        clearMessage = nil
        defer { isLoading = false }
        let repo = SettingsRepository(client: store.makeClient())
        do {
            let (_, loaded) = try await repo.load()
            values = loaded
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Speichern (Booleans als echte JSON-Bools).
    public func save(onSessionExpired: () -> Void) async {
        isSaving = true
        self.error = nil
        clearMessage = nil
        defer { isSaving = false }
        let repo = SettingsRepository(client: store.makeClient())
        do {
            values = try await repo.save(values)
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Cache leeren (Anzahl melden, Einstellungen bleiben erhalten).
    public func clearCache(onSessionExpired: () -> Void) async {
        isClearing = true
        self.error = nil
        clearMessage = nil
        defer { isClearing = false }
        let repo = SettingsRepository(client: store.makeClient())
        do {
            let count = try await repo.clearCache()
            clearMessage = "Cache geleert (\(count) Dateien)."
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Abmelden (serverseitig best-effort, lokal immer).
    public func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }
        let repo = AuthRepository(client: store.makeClient())
        try? await repo.logout()
        store.clear()
    }
}

/// Geräte-Logik (Paket A): eigene Sitzungen listen und widerrufen.
@MainActor
@Observable
public final class DevicesViewModel {
    public var devices: [DeviceInfo] = []
    public var isLoading = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public func load(onSessionExpired: () -> Void) async {
        isLoading = true
        self.error = nil
        defer { isLoading = false }
        let repo = SettingsRepository(client: store.makeClient())
        do {
            devices = try await repo.devices()
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    public func revoke(_ device: DeviceInfo, onSessionExpired: () -> Void) async {
        self.error = nil
        let repo = SettingsRepository(client: store.makeClient())
        do {
            try await repo.revokeDevice(id: device.id)
            devices.removeAll { $0.id == device.id }
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }
}
