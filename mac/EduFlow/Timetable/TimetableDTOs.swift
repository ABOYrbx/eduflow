import Foundation

/// Stunde 1:1 zum Web-Bauer (`app.py` `lesson_to_dict` plus
/// `merge_lernzeit`: Lernzeit-Blöcke zusammengefasst mit `period`
/// als Spanne, `row_period` und `rowspan`).
public struct Lesson: Decodable, Equatable, Sendable {
    public var period: String = ""
    public var time: String = ""
    public var title: String = ""
    public var isLernzeit: Bool = false
    public var teachers: String = ""
    public var rooms: String = ""
    public var isCancelled: Bool = false
    public var isEvent: Bool = false
    public var isOnline: Bool = false
    public var rowPeriod: String = ""
    public var rowspan: Int = 1

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        period = (try? box.decodeIfPresent(String.self, forKey: .period)) ?? ""
        time = (try? box.decodeIfPresent(String.self, forKey: .time)) ?? ""
        title = (try? box.decodeIfPresent(String.self, forKey: .title)) ?? ""
        isLernzeit = (try? box.decodeIfPresent(Bool.self, forKey: .isLernzeit)) ?? false
        teachers = (try? box.decodeIfPresent(String.self, forKey: .teachers)) ?? ""
        rooms = (try? box.decodeIfPresent(String.self, forKey: .rooms)) ?? ""
        isCancelled = (try? box.decodeIfPresent(Bool.self, forKey: .isCancelled)) ?? false
        isEvent = (try? box.decodeIfPresent(Bool.self, forKey: .isEvent)) ?? false
        isOnline = (try? box.decodeIfPresent(Bool.self, forKey: .isOnline)) ?? false
        rowPeriod = (try? box.decodeIfPresent(String.self, forKey: .rowPeriod)) ?? period
        rowspan = (try? box.decodeIfPresent(Int.self, forKey: .rowspan)) ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case period, time, title, isLernzeit, teachers, rooms
        case isCancelled, isEvent, isOnline, rowPeriod, rowspan
    }

    public var uid: String { period + time + title }
}

/// `GET /timetable/day` → Tag, deutsche Bezeichnung, Vor-/Folgetag,
/// Heute-Datum, Stunden und Cache-Info.
public struct TimetableDayResponse: Decodable, Sendable {
    public var day: String = ""
    public var dayLabel: String = ""
    public var prevDay: String = ""
    public var nextDay: String = ""
    public var today: String = ""
    public var lessons: [Lesson] = []
    public var cacheInfo: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? box.decodeIfPresent(String.self, forKey: .day)) ?? ""
        dayLabel = (try? box.decodeIfPresent(String.self, forKey: .dayLabel)) ?? ""
        prevDay = (try? box.decodeIfPresent(String.self, forKey: .prevDay)) ?? ""
        nextDay = (try? box.decodeIfPresent(String.self, forKey: .nextDay)) ?? ""
        today = (try? box.decodeIfPresent(String.self, forKey: .today)) ?? ""
        lessons = (try? box.decodeIfPresent([Lesson].self, forKey: .lessons)) ?? []
        cacheInfo = try? box.decodeIfPresent(String.self, forKey: .cacheInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case day, dayLabel, prevDay, nextDay, today, lessons, cacheInfo
    }
}

/// Ein Wochentag (Mo–Fr, ganztägige Events herausgefiltert wie im Web).
public struct TimetableWeekDay: Decodable, Sendable {
    public var date: String = ""
    public var dayName: String = ""
    public var dayDate: String = ""
    public var isToday: Bool = false
    public var lessons: [Lesson] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? box.decodeIfPresent(String.self, forKey: .date)) ?? ""
        dayName = (try? box.decodeIfPresent(String.self, forKey: .dayName)) ?? ""
        dayDate = (try? box.decodeIfPresent(String.self, forKey: .dayDate)) ?? ""
        isToday = (try? box.decodeIfPresent(Bool.self, forKey: .isToday)) ?? false
        lessons = (try? box.decodeIfPresent([Lesson].self, forKey: .lessons)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case date, dayName, dayDate, isToday, lessons
    }
}

/// `GET /timetable/week` → Montag, Wochenbezeichnung, Mo–Fr, Cache-Info.
public struct TimetableWeekResponse: Decodable, Sendable {
    public var day: String = ""
    public var monday: String = ""
    public var weekLabel: String = ""
    public var days: [TimetableWeekDay] = []
    public var cacheInfo: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? box.decodeIfPresent(String.self, forKey: .day)) ?? ""
        monday = (try? box.decodeIfPresent(String.self, forKey: .monday)) ?? ""
        weekLabel = (try? box.decodeIfPresent(String.self, forKey: .weekLabel)) ?? ""
        days = (try? box.decodeIfPresent([TimetableWeekDay].self, forKey: .days)) ?? []
        cacheInfo = try? box.decodeIfPresent(String.self, forKey: .cacheInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case day, monday, weekLabel, days, cacheInfo
    }
}

/// Aktuelle und nächste Stunde wie die Web-Übersicht (`app.py`):
/// laufende nicht entfallene Stunde, sonst nächste kommende; keine
/// Veranstaltungen. Zeitspanne `HH:MM–HH:MM` (Gedankenstrich).
/// Reine Logik (offline testbar, gegen feste Zeiten).
public enum CurrentLesson {
    public static func range(of time: String) -> (start: Int, end: Int)? {
        let parts = time.split(separator: "–")
        guard parts.count == 2,
            let start = minutes(String(parts[0])),
            let end = minutes(String(parts[1]))
        else {
            return nil
        }
        return (start, end)
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }
        return hour * 60 + minute
    }

    /// `(aktuelle, nächste)` aus den Tagesstunden plus Minuten seit Mitternacht.
    public static func of(_ lessons: [Lesson], nowMinutes: Int) -> (current: Lesson?, next: Lesson?) {
        var current: Lesson?
        var next: Lesson?
        for lesson in lessons {
            guard let span = range(of: lesson.time),
                !lesson.isCancelled,
                !lesson.isEvent
            else {
                continue
            }
            if current == nil, span.start <= nowMinutes, nowMinutes <= span.end {
                current = lesson
            }
            if next == nil, nowMinutes < span.start {
                next = lesson
            }
            if current != nil, next != nil {
                break
            }
        }
        return (current, next)
    }
}
