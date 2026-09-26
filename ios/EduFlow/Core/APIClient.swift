import Foundation

// MARK: - Netzwerk (Paket 0)
//
// Genau eine Client-Erzeugung pro Basis-URL + Token.
// Bearer-Token per Request (außer NO_AUTH_SUFFIXES); Ausnahme:
// Datei-Downloads hängen zusätzlich ?token= an (wie das Backend erlaubt).

final class APIClient {
    /// Pfade ohne Bearer-Token (System + Login-Ablauf).
    static let noAuthSuffixes = ["health", "openapi.json", "auth/login", "auth/2fa"]

    private let baseURL: URL
    private let tokenProvider: () -> String?
    private let session: URLSession

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: URL, tokenProvider: @escaping () -> String?) {
        var normalized = baseURL.absoluteString
        if !normalized.hasSuffix("/") { normalized += "/" }
        self.baseURL = URL(string: normalized) ?? baseURL
        self.tokenProvider = tokenProvider
        self.session = URLSession.shared
    }

    // MARK: Anfragen

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        let data = try await perform(path: path, method: "GET", query: query, body: nil)
        return try Self.decoder.decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await perform(path: path, method: "POST", query: [:], body: body)
        return try Self.decoder.decode(T.self, from: data)
    }

    func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = try await perform(path: path, method: "PUT", query: [:], body: body)
        return try Self.decoder.decode(T.self, from: data)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        let data = try await perform(path: path, method: "DELETE", query: [:], body: nil)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Download-URL für native Downloader (mit ?token=, weil dort
    /// nicht immer Header gesetzt werden können).
    /// Kompatibilität — bevorzugt attachmentDownloadURL mit `?dl=`
    /// (Kurzzeit-Token, landet nicht als Langzeit-Secret in Server-Logs).
    func attachmentURL(messageID: String, index: Int) -> URL? {
        guard let token = tokenProvider(), !token.isEmpty else { return nil }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("messages/\(messageID)/attachments/\(index)"),
            resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps?.url
    }

    /// Download-URL mit Kurzzeit-Token (`?dl=`, pro Datei, wenige Minuten
    /// gültig — wie Android MessagesRepository.attachmentUrl). Additiv zu
    /// attachmentURL, keine bestehende Signatur geändert.
    func attachmentDownloadURL(messageID: String, index: Int, dlToken: String) -> URL? {
        guard !dlToken.isEmpty else { return nil }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("messages/\(messageID)/attachments/\(index)"),
            resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "dl", value: dlToken)]
        return comps?.url
    }

    // MARK: Kern

    private func perform(
        path: String,
        method: String,
        query: [String: String?],
        body: [String: Any]?
    ) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { comps?.queryItems = items }
        guard let url = comps?.url else {
            throw APIError(code: "VALIDATION",
                           message: APIError.message(for: "VALIDATION"),
                           httpStatus: 0)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let needsAuth = !Self.noAuthSuffixes.contains { path.hasSuffix($0) }
        if needsAuth, let token = tokenProvider(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError(code: "UPSTREAM",
                           message: APIError.message(for: "UPSTREAM"),
                           httpStatus: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw parseError(data: data, status: status)
        }
        return data
    }

    private func parseError(data: Data, status: Int) -> APIError {
        if let dto = try? Self.decoder.decode(APIErrorDTO.self, from: data),
           !dto.code.isEmpty {
            let msg = dto.error.isEmpty ? APIError.message(for: dto.code) : dto.error
            return APIError(code: dto.code, message: msg, httpStatus: status)
        }
        return APIError(code: "UPSTREAM",
                        message: APIError.message(for: "UPSTREAM"),
                        httpStatus: status)
    }
}
