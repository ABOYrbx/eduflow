import Foundation

/// Noten-Logik (Halbjahr-Tabs, Suche, Schnitt).
@MainActor
@Observable
public final class GradesViewModel {
    public var items: [GradeDTO] = []
    public var total: Int = 0
    public var cacheInfo: String?
    public var tab: HalfYear = .all
    public var search = ""
    public var isLoading = false
    public var isLoadingMore = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public var tabs: [HalfYear] { HalfYear.tabs(for: items) }

    public var canLoadMore: Bool { items.count < total }

    /// Noten im gewählten Tab plus Suche (Fächer alphabetisch, Noten
    /// neueste zuerst wie im Web).
    public var visible: [(subject: String, grades: [GradeDTO], average: Double?)] {
        let inTab = items.filter { item in
            guard tab != .all else { return true }
            return HalfYear.key(for: item.dateIso) == tab
        }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = inTab.filter { item in
            guard !needle.isEmpty else { return true }
            let hay = [
                item.title, item.subject, item.teacher, item.comment,
                item.gradeDisplay, item.gradeSub,
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return hay.contains(needle)
        }
        var groups: [String: [GradeDTO]] = [:]
        for item in matching {
            groups[item.subject ?? "Sonstiges", default: []].append(item)
        }
        return groups.keys.sorted().map { subject in
            let grades = (groups[subject] ?? []).sorted {
                ($0.sortKey ?? "") > ($1.sortKey ?? "")
            }
            return (subject, grades, GradesAverage.of(grades))
        }
    }

    public var tabAverage: Double? {
        let inTab = items.filter { item in
            guard tab != .all else { return true }
            return HalfYear.key(for: item.dateIso) == tab
        }
        return GradesAverage.of(inTab)
    }

    public func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await repo().list(offset: 0, refresh: refresh)
            items = response.items
            total = response.total
            cacheInfo = response.cacheInfo
            if !tabs.contains(tab) {
                tab = .all
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
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    public func loadMore(onSessionExpired: () -> Void) async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await repo().list(offset: items.count)
            items += response.items
            total = response.total
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
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
        }
    }

    private func repo() -> GradesRepository {
        GradesRepository(client: store.makeClient())
    }
}
