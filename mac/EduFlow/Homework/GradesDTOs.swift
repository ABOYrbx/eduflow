import Foundation

/// Tolerante Kennung (EduPage liefert Zahlen oder Zeichenketten;
/// vergleiche Rohwert in `grade_to_dict`).
public enum GradeID: Decodable, Hashable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let value = try? box.decode(Int.self) {
            self = .int(value)
        } else if let value = try? box.decode(String.self) {
            self = .string(value)
        } else {
            self = .string("")
        }
    }

    public var raw: String {
        switch self {
        case .int(let value): return String(value)
        case .string(let value): return value
        }
    }
}

/// Note 1:1 zum Web-Bauer (`app.py` `grade_to_dict`, Cache-Reihenfolge).
public struct GradeDTO: Decodable, Sendable {
    public var id: GradeID?
    public var title: String?
    public var subject: String?
    public var teacher: String?
    public var dateDisplay: String?
    public var dateIso: String?
    public var sortKey: String?
    public var comment: String?
    public var gradeDisplay: String?
    public var gradeNum: Double?
    public var weight: Double?
    public var weightDisplay: String?
    public var gradeSub: String?
    public var badge: String?
    public var classAvg: Double?
    public var classAvgDisplay: String?
    public var isClassic: Bool?

    public init() {}

    public var uid: String { id?.raw ?? UUID().uuidString }
}

/// `GET /grades` → Hülle plus Cache-Info (keine neuen Filter, keine
/// neue Sortierung).
public struct GradesListResponse: Decodable, Sendable {
    public var items: [GradeDTO] = []
    public var total: Int = 0
    public var limit: Int = 50
    public var offset: Int = 0
    public var cacheInfo: String?

    public init() {}
}

/// Gewichteter Schnitt wie `grades_average` in `app.py`: klassische
/// Noten im gültigen Bereich (1 bis 6) mit Gewichtung, auf zwei Stellen
/// gerundet. Reine Logik (offline testbar).
public enum GradesAverage {
    public static func of(_ items: [GradeDTO]) -> Double? {
        var total = 0.0
        var weights = 0.0
        for item in items {
            guard let num = item.gradeNum, item.isClassic == true, (1...6).contains(num) else { continue }
            let weight = ((item.weight ?? 0) > 0) ? (item.weight ?? 1) : 1
            total += num * weight
            weights += weight
        }
        guard weights > 0 else { return nil }
        return (total / weights * 100).rounded() / 100
    }

    public static func display(_ average: Double?) -> String {
        guard let average else { return "–" }
        let formatted = String(format: "%.2f", average)
        return formatted.replacingOccurrences(of: ".", with: ",")
    }
}

/// Halbjahr-Ableitung wie die Web-Route für Noten: Schuljahr September
/// bis August, September bis Januar erstes, Februar bis August zweites
/// Halbjahr. Reine Logik (offline testbar).
public enum HalfYear: Hashable, Sendable {
    case half(yearStart: Int, half: Int)
    case all

    /// Schlüssel aus ISO-Datum (`YYYY-MM-DD`), sonst nil.
    public static func key(for dateIso: String?) -> HalfYear? {
        guard let dateIso, dateIso.count >= 7 else { return nil }
        let parts = dateIso.split(separator: "-")
        guard parts.count >= 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            (1...12).contains(month)
        else {
            return nil
        }
        if month >= 9 {
            return .half(yearStart: year, half: 1)
        } else if month == 1 {
            return .half(yearStart: year - 1, half: 1)
        } else {
            return .half(yearStart: year - 1, half: 2)
        }
    }

    public var label: String {
        switch self {
        case .all:
            return NSLocalizedString("grades_halfyear_all", value: "All", comment: "Noten: Gesamt-Tab")
        case .half(let yearStart, let half):
            return String(format: NSLocalizedString("grades_halfyear_format", value: "Semester %d (%d/%@)", comment: "Noten: Halbjahr-Label"), half, yearStart, String(String(yearStart + 1).suffix(2)))
        }
    }

    /// Tabs aus den geladenen Noten (neuestes zuerst plus Gesamt-Anhang).
    public static func tabs(for items: [GradeDTO]) -> [HalfYear] {
        var seen: [HalfYear] = []
        for item in items {
            guard let key = key(for: item.dateIso), !seen.contains(key) else { continue }
            seen.append(key)
        }
        seen.sort { left, right in
            switch (left, right) {
            case (.half(let ly, let lh), .half(let ry, let rh)):
                if ly != ry { return ly > ry }
                return lh > rh
            case (.half, .all): return true
            case (.all, .half): return false
            case (.all, .all): return false
            }
        }
        seen.append(.all)
        return seen
    }
}
