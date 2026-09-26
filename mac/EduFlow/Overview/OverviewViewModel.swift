import Foundation

/// Übersichts-Logik (Paket D): Uhr, ungelesene Nachrichten, offene
/// Hausaufgaben, aktuelle/nächste Stunde, Essen-heute, Wetterkarte.
/// Wiederverwendet die Listen aus den Paketen B und C (keine eigene
/// Server-Logik); Teilergebnisse bleiben sichtbar, Fehler werden
/// einzeln gemeldet.
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
    public var homeworkError: APIError?
    public var lessons: [Lesson] = []
    public var lessonsError: APIError?
    public var essen = EssenResponse()
    public var essenError: APIError?
    public var essenDay = 0
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
        async let homeworkTask = Self.capture {
            try await HomeworkRepository(client: client)
                .list(status: HomeworkStatusFilter.offen, limit: max(settings.ovHomework, 1), refresh: refresh)
        }
        async let dayTask = Self.capture {
            try await TimetableRepository(client: client).day(nil, refresh: refresh)
        }
        async let essenTask = Self.capture {
            try await MetaRepository(client: client).essen(refresh: refresh)
        }
        let (messagesResult, homeworkResult, dayResult, essenResult) =
            await (messagesTask, homeworkTask, dayTask, essenTask)
        var expired = false
        switch messagesResult {
        case .success(let page):
            messages = page.items
            messagesTotal = page.total
            messagesError = nil
        case .failure(let error):
            messages = []
            messagesError = error
            expired = expired || SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn)
        }
        switch homeworkResult {
        case .success(let response):
            homework = response.items
            homeworkOpen = response.counts?.offen ?? response.total
            homeworkOverdue = response.counts?.ueberfaellig ?? 0
            homeworkDone = response.counts?.erledigt ?? 0
            homeworkError = nil
        case .failure(let error):
            homework = []
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
        switch essenResult {
        case .success(let response):
            essen = response
            essenError = nil
            essenDay = Self.essenStartDay(response: response)
        case .failure(let error):
            // Essen braucht kein Login: nur Fehlertext, nie Abmelden.
            essenError = error
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
        let valid = ["messages", "homework", "weather", "lunch"]
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
            orderSaveError = APIError.germanFallback(for: ErrorCodes.upstream)
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
                message: "Bitte eine Stadt in den Einstellungen eintragen."
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
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    /// Aktuelle und nächste Stunde aus den Tagesstunden (wie im Web).
    public func currentAndNext(now: Date = Date()) -> (current: Lesson?, next: Lesson?) {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return CurrentLesson.of(lessons, nowMinutes: minutes)
    }

    /// Essens-Blätterer startet beim heutigen Tag (sonst Montag).
    nonisolated public static func essenStartDay(response: EssenResponse) -> Int {
        guard let today = response.today else { return 0 }
        return max(EssenDays.order.firstIndex(of: today) ?? 0, 0)
    }

    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, APIError> {
        do {
            return .success(try await work())
        } catch let apiError as APIError {
            return .failure(apiError)
        } catch {
            return .failure(APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            ))
        }
    }
}
