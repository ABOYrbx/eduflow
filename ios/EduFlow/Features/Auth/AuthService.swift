import Foundation

// MARK: - Auth + Einstellungen + Geräte (Paket A, nur gegen Paket 0)
//
// POST auth/login ({username, password, subdomain?, device?}) →
// ok (token, expires, subdomain, username) oder 2fa_required
// (pending_token, message). Clientseitige Validierung wie Android.

enum LoginResult {
    case loggedIn(token: String, expires: String, subdomain: String, username: String)
    case twoFaRequired(pendingToken: String, message: String)
}

final class AuthService {
    private let client: () -> APIClient
    private let store: TokenStore

    init(client: @escaping () -> APIClient, store: TokenStore) {
        self.client = client
        self.store = store
    }

    @discardableResult
    func login(username: String, password: String,
               subdomain: String, device: String) async throws -> LoginResult {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            throw APIError(code: "VALIDATION",
                           message: APIError.message(for: "VALIDATION"),
                           httpStatus: 0)
        }
        let raw: RawLoginResponse = try await client().post(
            "auth/login",
            body: ["username": name,
                   "password": password,
                   "subdomain": subdomain,
                   "device": device])
        if raw.status == "2fa_required", let pending = raw.pendingToken {
            return .twoFaRequired(pendingToken: pending, message: raw.message ?? "")
        }
        guard raw.status == "ok",
              let token = raw.token,
              let sub = raw.subdomain,
              let user = raw.username else {
            throw APIError(code: "UPSTREAM",
                           message: APIError.message(for: "UPSTREAM"),
                           httpStatus: 0)
        }
        await store.save(token: token, expires: raw.expires ?? "",
                         subdomain: sub, username: user)
        return .loggedIn(token: token, expires: raw.expires ?? "",
                         subdomain: sub, username: user)
    }

    @discardableResult
    func submit2FA(pendingToken: String, code: String) async throws -> LoginResult {
        let raw: RawLoginResponse = try await client().post(
            "auth/2fa",
            body: ["pending_token": pendingToken, "code": code])
        guard raw.status == "ok",
              let token = raw.token,
              let sub = raw.subdomain,
              let user = raw.username else {
            throw APIError(code: "UPSTREAM",
                           message: APIError.message(for: "UPSTREAM"),
                           httpStatus: 0)
        }
        await store.save(token: token, expires: raw.expires ?? "",
                         subdomain: sub, username: user)
        return .loggedIn(token: token, expires: raw.expires ?? "",
                         subdomain: sub, username: user)
    }

    /// Logout (best-effort) + lokaler Store-clear gilt immer.
    func logout() async {
        let _: StatusDTO? = try? await client().post("auth/logout", body: nil)
        await store.clear()
    }

    func refresh() async throws {
        let raw: RawLoginResponse = try await client().post("auth/refresh", body: nil)
        if let token = raw.token, let sub = raw.subdomain, let user = raw.username {
            await store.save(token: token, expires: raw.expires ?? "",
                             subdomain: sub, username: user)
        }
    }

    func me() async throws -> MeDTO {
        try await client().get("me")
    }

    func devices() async throws -> DevicesDTO {
        try await client().get("devices")
    }

    func revokeDevice(id: String) async throws {
        let _: StatusDTO = try await client().delete("devices/\(id)")
    }
}

// MARK: - Einstellungen + Cache (Paket G, Parität mit Web)

final class SettingsService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    func load() async throws -> (SettingsResponse, SettingsValues) {
        let res: SettingsResponse = try await client().get("settings")
        return (res, SettingsValues.from(res.values))
    }

    /// Werte speichern (Booleans als echte JSON-bools, wie api/settings.py).
    func save(_ values: SettingsValues) async throws -> SettingsValues {
        let body: [String: Any] = [
            "landing": values.landing,
            "hw_status": values.hwStatus,
            "hw_tests": values.hwTests,
            "ov_unread": values.ovUnread,
            "ov_homework": values.ovHomework,
            "ov_wetter": values.ovWetter,
            "wetter_city": values.wetterCity,
        ]
        let res: SettingsResponse = try await client().put("settings", body: body)
        return SettingsValues.from(res.values)
    }

    func clearCache() async throws -> CacheClearResponse {
        try await client().post("cache-clear", body: nil)
    }
}
