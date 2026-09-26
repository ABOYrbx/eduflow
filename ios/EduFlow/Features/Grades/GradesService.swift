import Foundation

// MARK: - Noten-Service (Paket C, nur gegen Paket 0)
//
// Parameter 1:1 wie die API (api/grades.py): limit (1..200), offset,
// refresh (0/1). Cache-Reihenfolge wie die Web-Seite, Fehler via APIError.

final class GradesService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    func list(limit: Int = 50, offset: Int = 0,
              refresh: Bool = false) async throws -> GradesListResponse {
        var query: [String: String?] = [
            "limit": String(min(max(limit, 1), 200)),
            "offset": String(max(offset, 0)),
        ]
        if refresh { query["refresh"] = "1" }
        return try await client().get("grades", query: query)
    }
}
