import Foundation

/// Stundenplan-Repository (Paket D, nur gegen Paket 0).
public struct TimetableRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Tagesansicht (Standard heute) mit Lernzeit-Blöcken,
    /// Entfall- und Online-Kennzeichen wie `/stundenplan`.
    public func day(_ day: String? = nil, refresh: Bool = false) async throws -> CachedTimetableDay {
        var items: [URLQueryItem] = []
        if let day, !day.isEmpty {
            items.append(URLQueryItem(name: "day", value: day))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.timetableDay, query: items, as: TimetableDayResponse.self
        )
        return CachedTimetableDay(
            response: try APIClient.decode(TimetableDayResponse.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Tagesansicht plus Zeitpunkt (nil = frisch vom Server).
    ///
    /// Leitet alle Felder durch, damit Aufrufer unverändert
    /// `.lessons`, `.dayLabel` usw. lesen können.
    public struct CachedTimetableDay: Sendable {
        public let response: TimetableDayResponse
        public let savedAt: Date?

        public var lessons: [Lesson] { response.lessons }
        public var day: String { response.day }
        public var dayLabel: String { response.dayLabel }
        public var prevDay: String { response.prevDay }
        public var nextDay: String { response.nextDay }
        public var today: String { response.today }
        public var cacheInfo: String? { response.cacheInfo }
        public var isFromCache: Bool { savedAt != nil }
    }

    /// Wochenansicht (Datum innerhalb der Woche) mit Mo–Fr plus
    /// Wochenbezeichnung; ganztägige Events herausgefiltert wie im Web.
    public func week(_ day: String? = nil, refresh: Bool = false) async throws -> CachedTimetableWeek {
        var items: [URLQueryItem] = []
        if let day, !day.isEmpty {
            items.append(URLQueryItem(name: "day", value: day))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.timetableWeek, query: items, as: TimetableWeekResponse.self
        )
        return CachedTimetableWeek(
            response: try APIClient.decode(TimetableWeekResponse.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Wochenansicht plus Zeitpunkt (nil = frisch vom Server).
    public struct CachedTimetableWeek: Sendable {
        public let response: TimetableWeekResponse
        public let savedAt: Date?

        public var days: [TimetableWeekDay] { response.days }
        public var day: String { response.day }
        public var monday: String { response.monday }
        public var weekLabel: String { response.weekLabel }
        public var cacheInfo: String? { response.cacheInfo }
        public var isFromCache: Bool { savedAt != nil }
    }
}
