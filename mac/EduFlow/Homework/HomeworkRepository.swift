import Foundation

/// Hausaufgaben-Repository (Paket C, nur gegen Paket 0).
public struct HomeworkRepository: Sendable {
    public static let defaultSince = "2000-01-01"
    public static let defaultLimit = 50

    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Liste mit Zeitraum, Statusfilter, Test-Einbeziehung, Suche und
    /// Paginierung (Antwort wie im Web: Sortierung überfällig zuerst,
    /// Zähler für offen, überfällig, erledigt und Papierkorb).
    public func list(
        since: String = defaultSince,
        status: String = HomeworkStatusFilter.alle,
        includeTests: Bool = false,
        query: String = "",
        limit: Int = defaultLimit,
        offset: Int = 0,
        refresh: Bool = false
    ) async throws -> HomeworkListResponse {
        var items = [
            URLQueryItem(name: "since", value: since),
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if includeTests {
            items.append(URLQueryItem(name: "include_tests", value: "1"))
        }
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let data = try await client.get(APIClient.Paths.homework, query: items)
        return try APIClient.decode(HomeworkListResponse.self, from: data)
    }

    /// Erledigt-Schalter (`{done}`, Default true; sofort sichtbar).
    @discardableResult
    public func setDone(id: Int, done: Bool = true) async throws -> HomeworkDTO {
        let payload = try APIClient.jsonData(["done": done])
        let data = try await client.post(APIClient.Paths.homeworkDone(id), body: payload)
        return try APIClient.decode(HomeworkDTO.self, from: data)
    }

    /// Papierkorb (`{hide}`; Zurückholen markiert gleichzeitig als offen).
    @discardableResult
    public func setTrash(id: Int, hide: Bool = true) async throws -> HomeworkDTO {
        let payload = try APIClient.jsonData(["hide": hide])
        let data = try await client.post(APIClient.Paths.homeworkTrash(id), body: payload)
        return try APIClient.decode(HomeworkDTO.self, from: data)
    }
}
