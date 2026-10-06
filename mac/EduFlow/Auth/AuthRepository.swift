import Foundation

/// Auth-Repository (Paket A, nur gegen Paket 0).
///
/// Schreibt nie selbst in den Speicher (das übernimmt das ViewModel),
/// damit Anmelden, Widerrufen und Leeren getrennt testbar bleiben.
public struct AuthRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Anmelden mit clientseitiger Pflichtfeld-Prüfung (ohne Netzaufruf).
    /// Subdomain leer bedeutet automatisch (wie `api/auth.py`).
    @discardableResult
    public func login(
        username: String,
        password: String,
        subdomain: String,
        device: String
    ) async throws -> LoginResult {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
        // Wie `auth.service.ts`: Subdomain trimmen + kleinschreiben,
        // leer bedeutet automatisch (Server-Default).
        let sub = subdomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = try APIClient.jsonData([
            "username": name,
            "password": password,
            "subdomain": sub,
            "device": device,
        ])
        let data = try await client.post(APIClient.Paths.login, body: body)
        return try Self.classify(try APIClient.decode(LoginResponse.self, from: data))
    }

    /// Zwei-Faktor-Abschluss (leerer Code wird clientseitig abgefangen).
    @discardableResult
    public func submit2FA(pendingToken: String, code: String) async throws -> LoginResult {
        let pending = pendingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty, !pin.isEmpty else {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
        let body = try APIClient.jsonData([
            "pending_token": pending,
            "code": pin,
        ])
        let data = try await client.post(APIClient.Paths.twoFA, body: body)
        return try Self.classify(try APIClient.decode(LoginResponse.self, from: data))
    }

    /// Abmelden (serverseitiger Widerruf; der Aufrufer leert den Speicher
    /// in jedem Fall — best-effort wie im Web).
    public func logout() async throws {
        let data = try await client.post(APIClient.Paths.logout)
        _ = try APIClient.decode(StatusResponse.self, from: data)
    }

    /// Token rotieren (Antwort wie Anmeldung mit Status ok).
    @discardableResult
    public func refresh() async throws -> LoginResult {
        let data = try await client.post(APIClient.Paths.refresh)
        return try Self.classify(try APIClient.decode(LoginResponse.self, from: data))
    }

    /// Eigener Benutzer (Subdomain und Benutzername des Token-Inhabers).
    public func me() async throws -> MeInfo {
        let payload = try await client.getCached(APIClient.Paths.me, as: MeInfo.self)
        return try APIClient.decode(MeInfo.self, from: payload.data)
    }

    // MARK: - Privat

    private static func classify(_ raw: LoginResponse) throws -> LoginResult {
        if raw.status == "2fa_required", let pending = raw.pendingToken {
            return .twoFaRequired(pendingToken: pending, message: raw.message ?? "")
        }
        guard raw.status == "ok",
            let token = raw.token,
            let subdomain = raw.subdomain,
            let username = raw.username
        else {
            throw APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
        return .loggedIn(
            token: token,
            expires: raw.expires ?? "",
            subdomain: subdomain,
            username: username
        )
    }
}
