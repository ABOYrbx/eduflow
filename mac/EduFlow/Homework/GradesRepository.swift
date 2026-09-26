import Foundation

/// Noten-Repository (Paket C, nur gegen Paket 0).
public struct GradesRepository: Sendable {
    public static let defaultLimit = 50

    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Liste in Cache-Reihenfolge (keine neuen Filter, keine neue
    /// Sortierung) mit Paginierung und Aktualisierungs-Schalter.
    public func list(
        limit: Int = defaultLimit,
        offset: Int = 0,
        refresh: Bool = false
    ) async throws -> GradesListResponse {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let data = try await client.get(APIClient.Paths.grades, query: items)
        return try APIClient.decode(GradesListResponse.self, from: data)
    }
}
