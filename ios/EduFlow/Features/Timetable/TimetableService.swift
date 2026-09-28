import Foundation

// MARK: - Stundenplan + Wetter (Paket D, nur gegen Paket 0)
//
// Parameter 1:1 wie die API (api/timetable.py, api/meta.py).
// Antwort-Dicts werden tolerant in DTOs dekodiert; Fehler via APIError.

final class TimetableService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    func day(_ day: String? = nil, refresh: Bool = false) async throws -> TimetableDayResponse {
        var query: [String: String?] = [:]
        if let day, !day.isEmpty { query["day"] = day }
        if refresh { query["refresh"] = "1" }
        return try await client().get("timetable/day", query: query)
    }

    func week(_ day: String? = nil, refresh: Bool = false) async throws -> TimetableWeekResponse {
        var query: [String: String?] = [:]
        if let day, !day.isEmpty { query["day"] = day }
        if refresh { query["refresh"] = "1" }
        return try await client().get("timetable/week", query: query)
    }
}

final class MetaService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    /// Wetter-Proxy (Schlüssel bleibt serverseitig).
    /// Ohne Ort VALIDATION, ohne Schlüssel CONFIG_MISSING (api/meta.py).
    func wetter(lat: Double? = nil, lon: Double? = nil,
                city: String? = nil) async throws -> WetterResponse {
        var query: [String: String?] = [:]
        if let lat, let lon {
            query["lat"] = String(lat)
            query["lon"] = String(lon)
        } else if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty {
            query["city"] = city
        }
        return try await client().get("wetter", query: query)
    }
}

// MARK: - Listen aus B/C für die Übersicht (nur lesend, gegen Paket 0)

/// Neueste Nachrichten (Top-Level, wie GET /messages, Web-Sortierung).
func fetchMessages(client: APIClient, limit: Int) async throws -> Page<MessageItem> {
    try await client.get("messages", query: ["limit": String(limit), "offset": "0"])
}

/// Hausaufgaben mit Zählern (Sortierung überfällig-zuerst, wie im Web).
func fetchHomework(client: APIClient, includeTests: Bool) async throws -> HomeworkListResponse {
    try await client.get("homework", query: [
        "status": "alle",
        "include_tests": includeTests ? "1" : "0",
        "limit": "50",
        "offset": "0",
    ])
}
