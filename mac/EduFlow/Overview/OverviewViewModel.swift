import Foundation

/// Übersichts-Logik: Uhr, Nachrichten, Hausaufgaben, aktuelle/nächste
/// Stunde, Wetterkarte. Wiederverwendet die Listen aus den Paketen B
/// und C (keine eigene Server-Logik); Teilergebnisse bleiben sichtbar,
/// Fehler werden einzeln gemeldet.
///
/// Hausaufgaben-Regel: `homework` enthält nur die tatsächlich geladene,
/// sichtbare Auswahl (ohne erledigte/versteckte Aufgaben); `homeworkOpen`
/// und `homeworkOverdue` werden daraus abgeleitet, damit Liste und Zähler
/// immer zusammenpassen. Die Server-Totale (`homeworkTotalOpen`,
/// `homeworkTotalOverdue`, `homeworkDone`) dienen nur Links, Hinweisen
/// und Leerzuständen.
@MainActor
@Observable
public final class OverviewViewModel {
    public var settings = SettingsValues()
    public var messages: [MessageDTO] = []
    public var messagesTotal: Int = 0
    public var messagesError: APIError?
    public var homework: [HomeworkDTO] = []
    public var homeworkOpen: Int = 0
    public var homeworkOverdue: Int = 0
    public var homeworkDone: Int = 0
    public var homeworkTotalOpen: Int = 0
    public var homeworkTotalOverdue: Int = 0
    public var homeworkHasMore = false
    public var homeworkError: APIError?
    public var lessons: [Lesson] = []
    public var lessonsError: APIError?
    public var wetter = WetterResponse()
    public var wetterError: APIError?
    public var isLoading = false
    public var isSavingOrder = false
    public var orderSaveError: String?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    /// Alle Bereiche laden (jeder für sich best-effort).
    public func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        defer { isLoading = false }
        let client = store.makeClient()
        let settingsRepo = SettingsRepository(client: client)
        if let (_, values) = try? await settingsRepo.load() {
            settings = values
        }
        async let messagesTask = Self.capture {
            try await MessagesRepository(client: client)
                .list(limit: max(settings.ovUnread, 1), refresh: refresh)
        }
        // Status "alle": Der Server sortiert überfällig zuerst, erledigte
        // zuletzt — so landen die relevanten Aufgaben auf Seite 1 und die
        // sichtbare Auswahl wird lokal daraus abgeleitet (statt globaler
        // Zähler neben einer gefilterten Teilliste).
        async let homeworkTask = Self.capture {
            try await HomeworkRepository(client: client)
                .list(status: HomeworkStatusFilter.alle, limit: max(settings.ovHomework, 1), refresh: refresh)
        }
        async let dayTask = Self.capture {
            try await TimetableRepository(client: client).day(nil, refresh: refresh)
        }
        let (messagesResult, homeworkResult, dayResult) =
            await (messagesTask, homeworkTask, dayTask)
        var expired = false
        switch messagesResult {
        case .success(let page):
            messages = page.items
            messagesTotal = page.total
            messagesError = nil
        case .failure(let error):
            messages = []
            messagesTotal = 0
            messagesError = error
            expired = expired || SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn)
        }
        switch homeworkResult {
        case .success(let response):
            let counts = response.counts ?? HomeworkCounts()
            homeworkTotalOpen = counts.offen
            homeworkTotalOverdue = counts.ueberfaellig
            homeworkDone = counts.erledigt
            // Sichtbar: nur tatsächlich geladene Aufgaben ohne erledigte
            // oder versteckte (Papierkorb) — in Server-Sortierung.
            let visible = response.items.filter {
                !$0.isHidden && !$0.isDone
                    && $0.status != HomeworkItemStatus.erledigt
                    && $0.status != HomeworkStatusFilter.papierkorb
            }
            homework = visible
            let overdue = visible.filter { $0.status == HomeworkItemStatus.ueberfaellig }.count
            homeworkOverdue = overdue
            homeworkOpen = visible.count - overdue
            // Relevante Totale (offen + überfällig); fällt auf die
            // sichtbare Anzahl zurück, damit die Angabe nie der Liste
            // widerspricht (z. B. bei fehlenden Zählern).
            let relevant = max(counts.offen + counts.ueberfaellig, visible.count)
            homeworkHasMore = relevant > visible.count
            homeworkError = nil
        case .failure(let error):
            homework = []
            homeworkOpen = 0
            homeworkOverdue = 0
            homeworkDone = 0
            homeworkTotalOpen = 0
            homeworkTotalOverdue = 0
            homeworkHasMore = false
            homeworkError = error
            expired = expired || SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn)
        }
        switch dayResult {
        case .success(let response):
            lessons = response.lessons
            lessonsError = nil
        case .failure(let error):
            lessons = []
            lessonsError = error
            expired = expired || SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn)
        }
        await loadWetter(client: client, expired: &expired)
        if expired {
            store.clear()
            onSessionExpired()
        }
    }

    public func saveOverviewOrder(_ order: [String], onSessionExpired: () -> Void) async -> Bool {
        isSavingOrder = true
        orderSaveError = nil
        defer { isSavingOrder = false }
        let valid = ["messages", "homework", "weather"]
        let unique = order.filter { valid.contains($0) }.reduce(into: [String]()) { result, key in
            if !result.contains(key) { result.append(key) }
        }
        let normalized = (unique + valid.filter { !unique.contains($0) }).joined(separator: ",")
        do {
            let repo = SettingsRepository(client: store.makeClient())
            var updated = settings
            updated.ovOrder = normalized
            settings = try await repo.save(updated)
            return true
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            }
            orderSaveError = apiError.message
        } catch {
            orderSaveError = APIError.englishFallback(for: ErrorCodes.upstream)
        }
        return false
    }

    private func loadWetter(client: APIClient, expired: inout Bool) async {
        guard settings.ovWetter else {
            wetter = WetterResponse()
            wetterError = nil
            return
        }
        let city = settings.wetterCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            wetter = WetterResponse()
            wetterError = APIError(
                code: ErrorCodes.validation,
                message: NSLocalizedString("overview_city_missing", value: "Please enter a city in settings.", comment: "Übersicht: Stadt fehlt")
            )
            return
        }
        do {
            wetter = try await MetaRepository(client: client).wetter(city: city)
            wetterError = nil
        } catch let apiError as APIError {
            expired = expired || SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn)
            wetter = WetterResponse()
            wetterError = apiError
        } catch {
            wetter = WetterResponse()
            wetterError = APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Relevante Gesamtzahl (offen + überfällig, nie kleiner als die
    /// sichtbare Auswahl) für Links und Leerzustände.
    public var homeworkRelevantTotal: Int {
        max(homeworkTotalOpen + homeworkTotalOverdue, homework.count)
    }

    /// In der Übersicht gezeigte Nachrichten (kompakt, max. 5).
    public var shownMessages: [MessageDTO] {
        Array(messages.prefix(5))
    }

    /// True, wenn mehr Nachrichten existieren als gezeigt werden
    /// (Server-Totale oder geladene, aber abgeschnittene Liste).
    public var messagesHasMore: Bool {
        messagesTotal > shownMessages.count || messages.count > shownMessages.count
    }

    /// Anzahl weiterer Nachrichten jenseits der gezeigten Auswahl.
    public var messagesMoreCount: Int {
        max(messagesTotal - shownMessages.count, messages.count - shownMessages.count, 0)
    }

    /// Anzahl weiterer Hausaufgaben jenseits der sichtbaren Auswahl.
    public var homeworkMoreCount: Int {
        max(homeworkRelevantTotal - homework.count, 0)
    }

    /// Aktuelle und nächste Stunde aus den Tagesstunden (wie im Web).
    public func currentAndNext(now: Date = Date()) -> (current: Lesson?, next: Lesson?) {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return CurrentLesson.of(lessons, nowMinutes: minutes)
    }

    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, APIError> {
        do {
            return .success(try await work())
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch {
            return .failure(APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            ))
        }
    }
}
