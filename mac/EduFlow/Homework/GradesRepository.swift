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
    ) async throws -> CachedGradesList {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.grades, query: items, as: GradesListResponse.self
        )
        return CachedGradesList(
            response: try APIClient.decode(GradesListResponse.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Notenliste plus Zeitpunkt (nil = frisch vom Server).
    public struct CachedGradesList: Sendable {
        public let response: GradesListResponse
        public let savedAt: Date?

        public var items: [GradeDTO] { response.items }
        public var total: Int { response.total }
        public var cacheInfo: String? { response.cacheInfo }
        public var isFromCache: Bool { savedAt != nil }
    }
}
