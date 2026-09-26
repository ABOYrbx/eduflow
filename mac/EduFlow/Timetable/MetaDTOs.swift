import Foundation

/// Gericht 1:1 aus dem Essensmodul (`essen.py`).
public struct EssenDish: Decodable, Sendable {
    public var text: String?
    public var price: String?

    public init() {}
}

/// Ein Wochentag im Essensplan (`{date, dishes, note}`).
public struct EssenDay: Decodable, Sendable {
    public var date: String?
    public var dishes: [EssenDish]?
    public var note: String?

    public init() {}
}

/// `GET /essen` → Woche, Bezeichnung, PDF-Quelle, Tage (Mo–Fr),
/// Heute-Tag, Cache-Kennzeichen und Cache-Info. Braucht kein Login.
public struct EssenResponse: Decodable, Sendable {
    public var week: String?
    public var label: String?
    public var sourceUrl: String?
    public var days: [String: EssenDay]?
    public var today: String?
    public var cached: Bool?
    public var cacheInfo: String?

    public init() {}
}

/// Wochentage in fester Reihenfolge (wie `essen.py` `DAY_NAMES`).
public enum EssenDays {
    public static let order = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"]
}

/// Wetter-Antwort 1:1 zum Web-Helfer (`app.py` `get_wetter_payload`).
public struct WetterToday: Decodable, Sendable {
    public var temp: Int?
    public var max: Int?
    public var min: Int?
    public var desc: String?
    public var icon: String?
    public var pop: Int?

    public init() {}
}

public struct WetterDay: Decodable, Sendable {
    public var max: Int?
    public var min: Int?
    public var desc: String?
    public var icon: String?
    public var pop: Int?
    public var label: String?

    public init() {}
}

public struct WetterHour: Decodable, Sendable {
    public var time: String?
    public var temp: Int?
    public var icon: String?
    public var desc: String?
    public var pop: Int?

    public init() {}
}

public struct WetterDetails: Decodable, Sendable {
    public var feelsLike: Int?
    public var humidity: Int?
    public var pressure: Int?
    public var windKmh: Int?
    public var windDir: String?
    public var clouds: Int?
    public var visibilityKm: Double?
    public var sunrise: String?
    public var sunset: String?

    public init() {}
}

/// `GET /wetter` → Stadt, Heute-, Morgen- und Übermorgen-Karte,
/// Stundenvorschau und Details (Schlüssel bleibt serverseitig).
public struct WetterResponse: Decodable, Sendable {
    public var city: String?
    public var today: WetterToday?
    public var tomorrow: WetterDay?
    public var day3: WetterDay?
    public var hourly: [WetterHour]?
    public var details: WetterDetails?

    public init() {}
}
