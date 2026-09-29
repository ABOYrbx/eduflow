import Foundation

/// Hausaufgaben-Logik (Filter, Zähler, Erledigt- und Papierkorb-Schalter).
@MainActor
@Observable
public final class HomeworkViewModel {
    public var items: [HomeworkDTO] = []
    public var total: Int = 0
    public var counts = HomeworkCounts()
    public var cacheInfo: String?
    public var status = HomeworkStatusFilter.alle
    public var includeTests = false
    public var query = ""
    public var isLoading = false
    public var isLoadingMore = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
        if let raw = UserDefaults.standard.string(forKey: "de.eduflow.hwStatus"),
            HomeworkStatusFilter.all.contains(raw)
        {
            status = raw
        }
    }

    public var canLoadMore: Bool { items.count < total }

    public func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        UserDefaults.standard.set(status, forKey: "de.eduflow.hwStatus")
        do {
            let response = try await repo().list(
                status: status,
                includeTests: includeTests,
                query: query,
                offset: 0,
                refresh: refresh
            )
            items = response.items
            total = response.total
            counts = response.counts ?? HomeworkCounts()
            cacheInfo = response.cacheInfo
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

    public func loadMore(onSessionExpired: () -> Void) async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await repo().list(
                status: status,
                includeTests: includeTests,
                query: query,
                offset: items.count
            )
            items += response.items
            total = response.total
            counts = response.counts ?? counts
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

    /// Erledigt umschalten (danach neu laden: Zähler plus Sortierung).
    public func toggleDone(_ item: HomeworkDTO, onSessionExpired: () -> Void) async {
        await mutate(item, onSessionExpired: onSessionExpired) {
            try await repo().setDone(id: $0.id, done: !$0.isDone)
        }
    }

    /// Papierkorb umschalten (Zurückholen markiert gleichzeitig als
    /// offen, wie im Web; danach neu laden).
    public func toggleTrash(_ item: HomeworkDTO, onSessionExpired: () -> Void) async {
        await mutate(item, onSessionExpired: onSessionExpired) {
            try await repo().setTrash(id: $0.id, hide: !$0.isHidden)
        }
    }

    private func mutate(
        _ item: HomeworkDTO,
        onSessionExpired: () -> Void,
        _ change: (HomeworkDTO) async throws -> HomeworkDTO
    ) async {
        error = nil
        do {
            _ = try await change(item)
            await load(onSessionExpired: onSessionExpired)
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

    private func repo() -> HomeworkRepository {
        HomeworkRepository(client: store.makeClient())
    }
}
