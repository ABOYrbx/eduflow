import Foundation

/// Stundenplan-Repository (Paket D, nur gegen Paket 0).
public struct TimetableRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Tagesansicht (Standard heute) mit Lernzeit-Blöcken,
    /// Entfall- und Online-Kennzeichen wie `/stundenplan`.
    public func day(_ day: String? = nil, refresh: Bool = false) async throws -> TimetableDayResponse {
        var items: [URLQueryItem] = []
        if let day, !day.isEmpty {
            items.append(URLQueryItem(name: "day", value: day))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let data = try await client.get(APIClient.Paths.timetableDay, query: items)
        return try APIClient.decode(TimetableDayResponse.self, from: data)
    }

    /// Wochenansicht (Datum innerhalb der Woche) mit Mo–Fr plus
    /// Wochenbezeichnung; ganztägige Events herausgefiltert wie im Web.
    public func week(_ day: String? = nil, refresh: Bool = false) async throws -> TimetableWeekResponse {
        var items: [URLQueryItem] = []
        if let day, !day.isEmpty {
            items.append(URLQueryItem(name: "day", value: day))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let data = try await client.get(APIClient.Paths.timetableWeek, query: items)
        return try APIClient.decode(TimetableWeekResponse.self, from: data)
    }
}
