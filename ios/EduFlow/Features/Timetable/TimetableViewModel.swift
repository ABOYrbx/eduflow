import Combine
import Foundation

// MARK: - Stundenplan-ViewModel (Paket D)
//
// Tag/Woche-Umschalter wie im Web (?view=), Tages-Navigation
// (Zurück / Heute / Weiter; in der Woche ±7 Tage).
// Lernzeit-Blöcke, Entfall-/Online-Kennzeichen kommen bereits
// zusammengefasst vom Server (merge_lernzeit, wie im Web).

@MainActor
final class TimetableViewModel: ObservableObject {
    enum View: String {
        case day, week
    }

    @Published var view: View = .day
    /// Angezeigter Tag (YYYY-MM-DD); in der Woche ein Tag daraus.
    @Published var day: String = ISODate.today
    @Published var dayData: TimetableDayResponse?
    @Published var weekData: TimetableWeekResponse?
    @Published var isLoading = false
    @Published var error: APIError?

    private let service: TimetableService

    init(service: TimetableService) {
        self.service = service
    }

    func load(refresh: Bool = false) async {
        isLoading = true
        self.error = nil
        do {
            if view == .week {
                weekData = try await service.week(day.isEmpty ? nil : day, refresh: refresh)
            } else {
                dayData = try await service.day(day.isEmpty ? nil : day, refresh: refresh)
            }
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    func setView(_ view: View) async {
        guard view != self.view else { return }
        self.view = view
        await load()
    }

    func setDay(_ day: String) async {
        self.day = day
        await load()
    }

    func goToday() async {
        await setDay(ISODate.today)
    }

    /// Einen Tag (Tagansicht) bzw. eine Woche (Wochenansicht) blättern.
    func step(_ days: Int) async {
        let hop = view == .week ? days * 7 : days
        await setDay(ISODate.shifted(day, by: hop) ?? ISODate.today)
    }
}

// MARK: - Tages-Helfer (YYYY-MM-DD, wie die API)

enum ISODate {
    static var today: String {
        formatted(Date())
    }

    static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func shifted(_ iso: String, by days: Int) -> String? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return nil }
        guard let n = Calendar(identifier: .iso8601).date(byAdding: .day, value: days, to: d) else { return nil }
        return f.string(from: n)
    }

    /// Aktuelle/nächste Stunde wie im Web (uebersicht): laufende nicht
    /// entfallene Stunde, sonst nächste kommende (keine Events).
    /// Zeitformat "HH:mm–HH:mm" (auch mit "-").
    static func currentAndNext(_ lessons: [Lesson]) -> (Lesson?, Lesson?) {
        let now = Date()
        let cal = Calendar.current
        let nowMins = (cal.component(.hour, from: now)) * 60 + cal.component(.minute, from: now)
        var current: Lesson?
        var next: Lesson?
        for lesson in lessons {
            guard let (start, end) = range(of: lesson) else { continue }
            if lesson.isCancelled == true { continue }
            if current == nil, start <= nowMins, nowMins <= end {
                current = lesson
            }
            if next == nil, start > nowMins {
                next = lesson
                if current != nil { break }
            }
        }
        return (current, next)
    }

    private static func range(of lesson: Lesson) -> (Int, Int)? {
        guard let time = lesson.time else { return nil }
        let sep = time.contains("–") ? "–" : "-"
        let parts = time.split(separator: Character(sep)).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let s = minutes(parts[0]), let e = minutes(parts[1]) else { return nil }
        return (s, e)
    }

    private static func minutes(_ hm: String) -> Int? {
        let p = hm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return p[0] * 60 + p[1]
    }
}
