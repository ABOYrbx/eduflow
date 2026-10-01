import Foundation

/// Tages- und Wochen-Datumshilfen (ISO `YYYY-MM-DD`). Reine Logik.
public enum TimetableDates {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static func today() -> String {
        formatter.string(from: Date())
    }

    public static func shifted(_ iso: String, days: Int) -> String {
        guard let date = formatter.date(from: iso) else { return iso }
        let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        return formatter.string(from: shifted)
    }
}

/// Stundenplan-Logik (Tag mit Zurück/Heute/Weiter, Woche in
/// Sieben-Tage-Schritten, Heute springt in die aktuelle Woche).
@MainActor
@Observable
public final class TimetableViewModel {
    public var weekMode = false
    public var day: String
    public var dayResponse = TimetableDayResponse()
    public var weekResponse = TimetableWeekResponse()
    public var isLoading = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
        day = TimetableDates.today()
    }

    public func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            if weekMode {
                weekResponse = try await repo().week(day, refresh: refresh)
            } else {
                dayResponse = try await repo().day(day, refresh: refresh)
            }
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
    }

    public func step(_ days: Int, onSessionExpired: () -> Void) async {
        day = TimetableDates.shifted(day, days: weekMode ? days * 7 : days)
        await load(onSessionExpired: onSessionExpired)
    }

    public func goToday(onSessionExpired: () -> Void) async {
        day = TimetableDates.today()
        await load(onSessionExpired: onSessionExpired)
    }

    private func repo() -> TimetableRepository {
        TimetableRepository(client: store.makeClient())
    }
}
