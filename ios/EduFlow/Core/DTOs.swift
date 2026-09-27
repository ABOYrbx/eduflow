import Foundation

// MARK: - EduFlow API v1 DTOs (Paket 0)
//
// 1:1 zu den Web-Dicts (event_to_dict, homework_to_dict,
// lesson_to_dict, grade_to_dict, get_wetter_payload).
// Unbekannte Felder werden ignoriert, fehlende sind nil — das
// garantiert Web- und App-Parität (wie Android ignoreUnknownKeys).

// MARK: Allgemein

/// Listen-Hülle aller Listen: {items, total, limit, offset} (BACKEND.md §1).
struct Page<T: Decodable>: Decodable {
    var items: [T] = []
    var total: Int = 0
    var limit: Int = 50
    var offset: Int = 0
}

/// Kanonische Fehlerantwort: {error, code} (api/core.py ERROR_CODES).
struct APIErrorDTO: Decodable {
    var error: String = ""
    var code: String = "UPSTREAM"
}

/// Status-Antwort {status} für logout / cache-clear / revoke.
struct StatusDTO: Decodable {
    var status: String = "ok"
}

/// Tolerante ID (EduPage liefert Zahlen oder Strings).
struct FlexibleID: Decodable, Hashable {
    let raw: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            raw = String(i)
        } else if let i = try? c.decode(Int64.self) {
            raw = String(i)
        } else {
            raw = (try? c.decode(String.self)) ?? ""
        }
    }
}

// MARK: Auth

/// POST auth/login → ok (token, expires, subdomain, username)
/// oder 2fa_required (pending_token, message).
struct RawLoginResponse: Decodable {
    var status: String?
    var token: String?
    var expires: String?
    var subdomain: String?
    var username: String?
    var pendingToken: String?
    var message: String?
}

struct MeDTO: Decodable {
    var subdomain: String = ""
    var username: String = ""
}

/// GET devices → eigene Tokens ohne Secrets (wie Web /einstellungen).
struct DeviceDTO: Decodable {
    var id: String = ""
    var short: String = ""
    var device: String = ""
    var created: String = ""
    var expires: String = ""
}

struct DevicesDTO: Decodable {
    var items: [DeviceDTO] = []
    var total: Int = 0
}

// MARK: Nachrichten (für Übersicht; volle Screens = offenes Paket)

/// Nachricht 1:1 zum Web-Bauer (app.py event_to_dict).
struct MessageItem: Decodable {
    var id: FlexibleID?
    var timestamp: String?
    var timestampIso: String?
    var author: String?
    var recipient: String?
    var type: String?
    var typeLabel: String?
    var text: String?
    var reactionCount: Int?
    var attachments: [MessageAttachment]?

    var uid: String { id?.raw ?? UUID().uuidString }

    /// Kartentext: einzeilig normalisierter Nachrichtentext (max. 220).
    /// (Kein Betreff — die API liefert kein Betreff-Feld.)
    var bodyLine: String {
        let flat = (text ?? "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let squeezed = flat.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if squeezed.isEmpty {
            return (typeLabel?.isEmpty == false) ? typeLabel! : (type ?? "")
        }
        return squeezed.count > 220 ? String(squeezed.prefix(220)) + "…" : squeezed
    }

    /// Initialen für den Avatar-Kreis.
    var initials: String {
        let words = (author ?? "").split(separator: " ")
        return String(words.prefix(2).compactMap { $0.first }.map(String.init).joined())
    }
}

struct MessageAttachment: Decodable {
    var name: String?
    var url: String?
}

// MARK: Hausaufgaben (für Übersicht; volle Screens = offenes Paket)

/// Hausaufgabe 1:1 zum Web-Bauer (app.py homework_to_dict + mark_hidden).
struct HomeworkItem: Decodable {
    var id: FlexibleID?
    var type: String?
    var typeLabel: String?
    var title: String?
    var description: String?
    var subject: String?
    var author: String?
    var assigned: String?
    var due: String?
    var dueDisplay: String?
    var status: String?
    var isDone: Bool?
    var isStarred: Bool?
    var isHidden: Bool?

    var uid: String { id?.raw ?? UUID().uuidString }
}

/// Zähler wie im Web (api/homework.py _build_view).
/// ACHTUNG: JSON-Key ist ascii "ueberfaellig" (ohne Umlaut).
struct HomeworkCounts: Decodable {
    var offen: Int = 0
    var ueberfaellig: Int = 0
    var erledigt: Int = 0
    var papierkorb: Int = 0
}

struct HomeworkListResponse: Decodable {
    var items: [HomeworkItem] = []
    var total: Int = 0
    var limit: Int = 50
    var offset: Int = 0
    var counts: HomeworkCounts?
    var cacheInfo: String?
}

// MARK: Stundenplan

/// Stunde 1:1 zum Web-Bauer (app.py lesson_to_dict + merge_lernzeit).
/// Lernzeit-Blöcke kommen zusammengefasst (period "2–3", rowspan > 1).
struct Lesson: Decodable {
    var period: String?
    var time: String?
    var title: String?
    var isLernzeit: Bool?
    var teachers: String?
    var rooms: String?
    var isCancelled: Bool?
    var isEvent: Bool?
    var isOnline: Bool?
    var rowPeriod: String?
    var rowspan: Int?

    var uid: String { (period ?? "") + (time ?? "") + (title ?? "") }
}

/// GET /timetable/day → Tag, deutsche Bezeichnung, Vor-/Folgetag, Stunden.
struct TimetableDayResponse: Decodable {
    var day: String = ""
    var dayLabel: String = ""
    var prevDay: String = ""
    var nextDay: String = ""
    var today: String = ""
    var lessons: [Lesson] = []
    var cacheInfo: String?
}

/// Ein Wochentag in der Wochenansicht (Mo–Fr, Events herausgefiltert).
struct TimetableWeekDay: Decodable, Identifiable {
    var date: String = ""
    var dayName: String = ""
    var dayDate: String = ""
    var isToday: Bool = false
    var lessons: [Lesson] = []

    var id: String { date }
}

/// GET /timetable/week → Montag, Wochenbezeichnung, Mo–Fr.
struct TimetableWeekResponse: Decodable {
    var day: String = ""
    var monday: String = ""
    var weekLabel: String = ""
    var days: [TimetableWeekDay] = []
    var cacheInfo: String?
}

// MARK: Nachrichten-Thread (Paket B)

// Likes/Antworten/Zusammenfassung aus app.py get_message_likes.
// GET /messages/{id}/thread und POST /messages/{id}/reply.
struct ThreadLike: Decodable {
    var name: String?
    var date: String?
}

struct ThreadReply: Decodable {
    var name: String?
    var date: String?
    var text: String?
}

struct ThreadSummary: Decodable {
    var total: Int = 0
    var likes: Int = 0
    var replies: Int = 0
    var seen: Int = 0
}

struct ThreadResponse: Decodable {
    var likes: [ThreadLike] = []
    var replies: [ThreadReply] = []
    var replyIds: [String] = []
    var summary: ThreadSummary?
    var cached: Bool = false
}

// MARK: Empfänger (Paket B)

// Empfänger für den Verfassen-Dialog: Lehrer + Mitschüler
// (app.py get_recipients). Liste: GET /recipients (Page-Hülle,
// nach Name sortiert).
struct RecipientItem: Decodable, Identifiable {
    var id: String = ""
    var name: String = ""
    var kind: String = ""
}

/// Listen-Filter aus dem Redesign-PNG (Screen 02):
/// Alle / Ungelesen (lokal) / Mit Dateien.
enum MsgFilter: String, CaseIterable {
    case alle = "Alle"
    case ungelesen = "Ungelesen"
    case mitDateien = "Mit Dateien"
}

/// Nachrichtentypen mit deutschem Label (app.py MESSAGE_TYPES + TYPE_LABELS).
/// Leerer Typ = alle nachrichtenartigen Typen (Web-Default).
enum MessageTypes {
    static let alle = ""
    static let sprava = "sprava"
    static let news = "news"
    static let anketa = "anketa"
    static let chat = "chat"
    static let genotif = "genotif"

    static let all = [alle, sprava, news, anketa, chat, genotif]

    static func label(_ type: String) -> String {
        switch type {
        case sprava: return "Nachricht"
        case news: return "Neuigkeit"
        case anketa: return "Umfrage"
        case chat: return "Chat"
        case genotif: return "Mitteilung"
        default: return "Alle"
        }
    }
}

/// Empfänger-ID-Format wie serverseitig (app.py _RECIPIENT_ID_RE):
/// Teacher|Student|StudentOnly|Parent|Rodic|Ucitel + Zahl.
/// Reine Logik (offline testbar, ohne Netzwerk).
enum RecipientIDs {
    static func isValid(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let pattern = "^(Teacher|Student|StudentOnly|Parent|Rodic|Ucitel)\\d+$"
        return t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func clean(_ raw: [String]) -> [String] {
        var seen: [String] = []
        for entry in raw {
            let id = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, isValid(id), !seen.contains(id) {
                seen.append(id)
            }
        }
        return seen
    }
}

/// POST /messages/read — alle aktuellen Nachrichten als gelesen.
struct MarkReadResponse: Decodable {
    var marked: Int = 0
}

/// POST /messages/download-token → Kurzzeit-Token für genau eine Datei
/// ({download_token, expires_in}, wenige Minuten gültig, `?dl=` statt
/// `?token=` — wie Android MessagesRepository.attachmentUrl).
struct DownloadTokenResponse: Decodable {
    var downloadToken: String = ""
    var expiresIn: Int = 0
}

// MARK: Hausaufgaben-Statusfilter (Paket C)

// Statusfilter wie Web + API (?status=...).
enum HomeworkStatusFilter {
    static let alle = "alle"
    static let offen = "offen"
    static let ueberfaellig = "überfällig"
    static let erledigt = "erledigt"
    static let papierkorb = "papierkorb"

    static let all = [alle, offen, ueberfaellig, erledigt, papierkorb]
}

/// Item-Statuswerte aus homework_to_dict (inkl. "heute fällig", "ohne Datum").
enum HomeworkItemStatus {
    static let ueberfaellig = "überfällig"
    static let heute = "heute fällig"
    static let offen = "offen"
    static let erledigt = "erledigt"
    static let ohneDatum = "ohne Datum"
}

// MARK: Noten (Paket C)

// Note 1:1 zum Web-Bauer (app.py grade_to_dict, Cache-Reihenfolge).
// GET /grades → GradesListResponse (Page-Hülle + Cache-Info).
struct GradeItem: Decodable {
    var id: FlexibleID?
    var title: String?
    var subject: String?
    var teacher: String?
    var dateDisplay: String?
    var dateIso: String?
    var sortKey: String?
    var comment: String?
    var gradeDisplay: String?
    var gradeNum: Double?
    var weight: Double?
    var weightDisplay: String?
    var gradeSub: String?
    var badge: String?
    var classAvg: Double?
    var classAvgDisplay: String?
    var isClassic: Bool?

    var uid: String { id?.raw ?? UUID().uuidString }
}

struct GradesListResponse: Decodable {
    var items: [GradeItem] = []
    var total: Int = 0
    var limit: Int = 50
    var offset: Int = 0
    var cacheInfo: String?
}

/// Gewichteter Schnitt über klassische 1–5-Noten (wie grades_average
/// in app.py: Gewichtung = importance). Reine Logik (offline testbar).
enum GradesAverage {
    static func of(_ items: [GradeItem]) -> Double? {
        var total = 0.0
        var weights = 0.0
        for item in items {
            guard let num = item.gradeNum, item.isClassic == true else { continue }
            let w = (item.weight ?? 0) > 0 ? (item.weight ?? 1) : 1
            total += num * w
            weights += w
        }
        guard weights > 0 else { return nil }
        return total / weights
    }

    static func display(_ avg: Double?) -> String {
        guard let avg else { return "–" }
        return String(format: "%.2f", locale: Locale(identifier: "de_DE"), avg)
            .replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: Wetter

struct WetterDay: Decodable {
    var max: Int?
    var min: Int?
    var desc: String?
    var icon: String?
    var pop: Int?
    var label: String?
}

struct WetterToday: Decodable {
    var temp: Int?
    var max: Int?
    var min: Int?
    var desc: String?
    var icon: String?
    var pop: Int?
}

struct WetterHour: Decodable {
    var time: String?
    var temp: Int?
    var icon: String?
    var desc: String?
    var pop: Int?
}

struct WetterDetails: Decodable {
    var feelsLike: Int?
    var humidity: Int?
    var pressure: Int?
    var windKmh: Int?
    var windDir: String?
    var clouds: Int?
    var visibilityKm: Double?
    var sunrise: String?
    var sunset: String?
}

/// GET /wetter → heute/morgen/übermorgen, Stunden, Details, Ort.
struct WetterResponse: Decodable {
    var city: String?
    var today: WetterToday?
    var tomorrow: WetterDay?
    var day3: WetterDay?
    var hourly: [WetterHour]?
    var details: WetterDetails?
}

// MARK: Einstellungen

/// Gemischter JSON-Wert (Schema-Defaults und Values sind skalar).
enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .null
        }
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .string(let s): return ["1", "true", "on"].contains(s.lowercased())
        case .int(let i): return i != 0
        default: return false
        }
    }
}

/// Einstellungen 1:1 zum Web-Schema (app.py SETTINGS_SCHEMA).
struct SettingSpec: Decodable {
    var key: String = ""
    var kind: String = "text"
    var label: String = ""
    var options: [[String]] = []
    var defaultValue: JSONValue?
    var min: Int?
    var max: Int?
    var hint: String?

    enum CodingKeys: String, CodingKey {
        case key, kind, label, options, min, max, hint
        case defaultValue = "default"
    }
}

struct SettingsResponse: Decodable {
    var schema: [SettingSpec] = []
    var values: [String: JSONValue] = [:]
}

struct CacheClearResponse: Decodable {
    var status: String = "ok"
    var cleared: Int = 0
}

/// Typisierte Sicht auf die Server-Werte (mit Fallback auf Defaults).
struct SettingsValues {
    var landing = "uebersicht"
    var hwStatus = "alle"
    var hwTests = false
    var ovUnread = 10
    var ovHomework = 10
    var ovWetter = true
    var wetterCity = ""

    static func from(_ values: [String: JSONValue]) -> SettingsValues {
        var out = SettingsValues()
        let landings = ["uebersicht", "dashboard", "hausaufgaben", "noten", "stundenplan"]
        if let s = values["landing"]?.string, landings.contains(s) { out.landing = s }
        let statuses = ["alle", "offen", "überfällig", "erledigt", "papierkorb"]
        if let s = values["hw_status"]?.string, statuses.contains(s) { out.hwStatus = s }
        if let v = values["hw_tests"] { out.hwTests = v.bool }
        if let i = values["ov_unread"]?.int { out.ovUnread = min(max(i, 1), 50) }
        if let i = values["ov_homework"]?.int { out.ovHomework = min(max(i, 1), 50) }
        if let v = values["ov_wetter"] { out.ovWetter = v.bool }
        if let s = values["wetter_city"]?.string { out.wetterCity = s }
        return out
    }
}
