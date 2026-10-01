import Foundation

/// Einziger Netzwerk-Client (Paket 0, eingefroren).
///
/// Deckt alle Routen der API-Version 1 aus `openapi.json` ab.
/// Ressourcen-Inhalte bleiben rohe Web-Daten (`Data`); typisierte
/// Objekte baut jedes Paket selbst per `decode`. Anfragen und Antworten
/// werden nie geloggt (Downloads tragen den Token in der URL).
public struct APIClient: Sendable {
    public var baseURL: @Sendable () -> String
    public var token: @Sendable () -> String?
    public var session: URLSession

    public init(
        baseURL: @escaping @Sendable () -> String,
        token: @escaping @Sendable () -> String?,
        session: URLSession = TokenStore.defaultSession()
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Gemeinsamer Decoder (tolerant wie der Web-Cache).
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Alle Routenpfade der API-Version 1 (Quelle: `openapi.json`).
    public enum Paths {
        public static let health = "health"
        public static let openAPI = "openapi.json"
        public static let login = "auth/login"
        public static let twoFA = "auth/2fa"
        public static let logout = "auth/logout"
        public static let refresh = "auth/refresh"
        public static let me = "me"
        public static let devices = "devices"
        public static func device(_ hash: String) -> String { "devices/\(hash)" }
        public static let settings = "settings"
        public static let cacheClear = "cache-clear"
        public static let messages = "messages"
        public static func thread(_ id: Int) -> String { "messages/\(id)/thread" }
        public static let markRead = "messages/read"
        public static let recipients = "recipients"
        public static let sendMessage = "messages/send"
        public static func reply(_ id: Int) -> String { "messages/\(id)/reply" }
        public static func attachment(_ id: Int, _ idx: Int) -> String {
            "messages/\(id)/attachments/\(idx)"
        }
        public static let downloadToken = "messages/download-token"
        public static let homework = "homework"
        public static func homeworkDone(_ id: Int) -> String { "homework/\(id)/done" }
        public static func homeworkTrash(_ id: Int) -> String { "homework/\(id)/trash" }
        public static let grades = "grades"
        public static let timetableDay = "timetable/day"
        public static let timetableWeek = "timetable/week"
        public static let schoolAgenda = "school/agenda"
        public static let substitutionsWeek = "substitutions/week"
        public static let wetter = "wetter"
        public static let wetterSuche = "wetter/suche"
    }

    /// Pfade ohne Bearer-Token (System plus Login-Ablauf).
    public static let noAuthSuffixes = [healthPath, openAPIPath, loginPath, twoFAPath]
    private static let healthPath = Paths.health
    private static let openAPIPath = Paths.openAPI
    private static let loginPath = Paths.login
    private static let twoFAPath = Paths.twoFA

    // MARK: - HTTP-Verben (generisch, Pakete bauen Query und Body)

    public func get(
        _ path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Data {
        let request = try buildRequest(path: path, query: query, authenticated: authenticated)
        return try await perform(request)
    }

    public func post(
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        var request = try buildRequest(path: path, query: query, authenticated: authenticated)
        request.httpMethod = "POST"
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    public func put(
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        var request = try buildRequest(path: path, query: query, authenticated: authenticated)
        request.httpMethod = "PUT"
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    public func delete(_ path: String, authenticated: Bool = true) async throws -> Data {
        var request = try buildRequest(path: path, authenticated: authenticated)
        request.httpMethod = "DELETE"
        return try await perform(request)
    }

    /// Datei-Download mit Query-Token (BACKEND.md §1: native Downloader
    /// setzen nicht immer Header). Liefert eine lokale Datei-URL.
    /// Mit Kurzzeit-Token (`?dl=`, empfohlen) entfällt `?token=`.
    public func download(
        _ path: String,
        query: [URLQueryItem] = [],
        useTokenQuery: Bool = true
    ) async throws -> URL {
        var items = query
        if useTokenQuery {
            items.append(URLQueryItem(name: "token", value: token() ?? ""))
        }
        let request = try buildRequest(path: path, query: items, authenticated: false)
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            throw APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
        return file
    }

    /// Gesundheit ohne Auth (für Abnahme und Start-Diagnose).
    public func health() async throws -> Health {
        let data = try await get(Paths.health, authenticated: false)
        return try Self.decode(Health.self, from: data)
    }

    // MARK: - Dekodieren und Body-Bau (Paket-Helfer)

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Wörterbuch mit exakten Backend-Schlüsseln zu JSON (Pakete bauen
    /// Bodies mit den Schlüsseln aus `api/*.py`, keine Umwandlung).
    public static func jsonData(_ dict: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: dict, options: [])
        } catch {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
    }

    // MARK: - Privat

    private func buildRequest(
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool
    ) throws -> URLRequest {
        let base = baseURL().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var parts = URLComponents(string: base + "/" + clean)
        if !query.isEmpty {
            parts?.queryItems = query
        }
        guard let url = parts?.url else {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let needsAuth = authenticated
            && !Self.noAuthSuffixes.contains(where: { clean.hasSuffix($0) })
        if needsAuth, let current = token(), !current.isEmpty {
            request.setValue("Bearer \(current)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw mapError(status: status, data: data)
        }
        return data
    }

    private func mapError(status: Int, data: Data) -> APIError {
        if let body = try? Self.decoder.decode(APIErrorBody.self, from: data),
            !body.code.isEmpty
        {
            let message = body.error.isEmpty
                ? APIError.englishFallback(for: body.code) : body.error
            return APIError(code: body.code, message: message, httpStatus: status)
        }
        return APIError(
            code: ErrorCodes.upstream,
            message: APIError.englishFallback(for: ErrorCodes.upstream),
            httpStatus: status
        )
    }
}
