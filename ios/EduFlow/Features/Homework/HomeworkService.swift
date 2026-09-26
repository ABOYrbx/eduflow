import Foundation

// MARK: - Hausaufgaben- + Noten-Service (Paket C, nur gegen Paket 0)
//
// Parameter 1:1 wie die API (api/homework.py, api/grades.py).
// Antwort-Dicts werden tolerant in DTOs dekodiert; Fehler via APIError.

final class HomeworkService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    func list(since: String? = nil, status: String = HomeworkStatusFilter.alle,
              includeTests: Bool = false, q: String = "",
              limit: Int = 50, offset: Int = 0,
              refresh: Bool = false) async throws -> HomeworkListResponse {
        var query: [String: String?] = [
            "status": status,
            "include_tests": includeTests ? "1" : "0",
            "limit": String(min(max(limit, 1), 200)),
            "offset": String(max(offset, 0)),
        ]
        if let since, !since.isEmpty { query["since"] = since }
        if !q.isEmpty { query["q"] = q }
        if refresh { query["refresh"] = "1" }
        return try await client().get("homework", query: query)
    }

    func setDone(id: String, done: Bool) async throws -> HomeworkItem {
        try await client().post("homework/\(id)/done", body: ["done": done])
    }

    func setTrash(id: String, hide: Bool) async throws -> HomeworkItem {
        try await client().post("homework/\(id)/trash", body: ["hide": hide])
    }
}
