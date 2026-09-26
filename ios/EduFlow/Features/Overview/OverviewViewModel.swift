import Combine
import Foundation

// MARK: - Übersicht-ViewModel (Paket D, Startseite)
//
// Wiederverwendet die Listen aus B/C gegen Paket 0:
// neueste Nachrichten (ov_unread-Limit), offene Hausaufgaben
// (ov_homework-Limit, überfällig zuerst wie im Web), heutige Stunden
// (aktuelle/nächste wie im Web), Essen-heute, Wetterkarte.

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var settings = SettingsValues()
    @Published var messages: [MessageItem] = []
    @Published var messagesTotal = 0
    @Published var homework: [HomeworkItem] = []
    @Published var homeworkCounts = HomeworkCounts()
    @Published var lessonsToday: [Lesson] = []
    @Published var currentLesson: Lesson?
    @Published var nextLesson: Lesson?
    @Published var essen: EssenResponse?
    /// Pager-Position im Essensplan (Mo–Fr, Start: heute).
    @Published var essenIndex = 0
    @Published var wetter: WetterResponse?
    @Published var wetterCity = ""
    @Published var wetterLoading = false
    @Published var wetterError: APIError?
    @Published var isLoading = false
    @Published var error: APIError?
    @Published var cacheInfo = ""

    private let client: () -> APIClient
    private let settingsService: SettingsService
    private let timetableService: TimetableService
    private let metaService: MetaService

    init(client: @escaping () -> APIClient,
         settingsService: SettingsService,
         timetableService: TimetableService,
         metaService: MetaService) {
        self.client = client
        self.settingsService = settingsService
        self.timetableService = timetableService
        self.metaService = metaService
    }

    func refresh() async {
        isLoading = true
        self.error = nil
        let settings: SettingsValues
        do {
            settings = try await settingsService.load().1
        } catch let e as APIError {
            self.error = e
            isLoading = false
            return
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
            isLoading = false
            return
        }
        self.settings = settings
        wetterCity = settings.wetterCity

        var firstError: APIError?
        do {
            let page: Page<MessageItem> = try await fetchMessages(
                client: client(), limit: min(max(settings.ovUnread, 1), 50))
            messages = page.items
            messagesTotal = page.total
        } catch let e as APIError {
            firstError = firstError ?? e
        } catch {
            firstError = firstError ?? APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        do {
            let page = try await fetchHomework(client: client(), includeTests: settings.hwTests)
            homework = page.items
                .filter { ($0.isDone ?? false) == false && ($0.isHidden ?? false) == false }
                .prefix(min(max(settings.ovHomework, 1), 50)).map { $0 }
            homeworkCounts = page.counts ?? HomeworkCounts()
            cacheInfo = page.cacheInfo ?? ""
        } catch let e as APIError {
            firstError = firstError ?? e
        } catch {
            firstError = firstError ?? APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        do {
            let day = try await timetableService.day()
            let lessons = day.lessons.filter { ($0.isEvent ?? false) == false }
            lessonsToday = lessons
            let (current, next) = ISODate.currentAndNext(lessons)
            currentLesson = current
            nextLesson = next
        } catch let e as APIError {
            firstError = firstError ?? e
        } catch {
            firstError = firstError ?? APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        do {
            let menu = try await metaService.essen()
            essen = menu
            if let today = menu.today, let idx = EssenDays.order.firstIndex(of: today) {
                essenIndex = idx
            } else {
                essenIndex = 0
            }
        } catch let e as APIError {
            firstError = firstError ?? e
        } catch {
            firstError = firstError ?? APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        // Wetter nur bei Anzeige-Wunsch und hinterlegter Stadt automatisch
        // laden (Stadt aus den Einstellungen); sonst manuell per Karte.
        if settings.ovWetter,
           !settings.wetterCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                wetter = try await metaService.wetter(city: settings.wetterCity)
            } catch let e as APIError {
                wetterError = e
            } catch {
                wetterError = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
            }
        }
        self.error = firstError
        isLoading = false
    }

    /// Essens-Pager (‹ › unten, wie im Web, Mo–Fr).
    func stepEssen(_ delta: Int) {
        essenIndex = min(max(essenIndex + delta, 0), EssenDays.order.count - 1)
    }

    /// Wetter laden (Ort per Stadt; Schlüssel bleibt serverseitig).
    func loadWetter() async {
        let city = wetterCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            wetterError = APIError(code: "VALIDATION", message: "Bitte eine Stadt eingeben.", httpStatus: 0)
            return
        }
        wetterLoading = true
        wetterError = nil
        do {
            wetter = try await metaService.wetter(city: city)
        } catch let e as APIError {
            wetterError = e
        } catch {
            wetterError = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        wetterLoading = false
    }
}
