import Combine
import Foundation

// MARK: - Hausaufgaben-ViewModel (Paket C)
//
// Liste mit Statusfilter, Suche (debounced), Tests-Schalter, Refresh;
// Paginierung (limit 50, Mehr laden); done/trash mit Pending-Schutz,
// nach Erfolg lokal nachgepflegt (Server ist Source of Truth beim
// nächsten Refresh, wie im Web nach POST + Reload).

@MainActor
final class HomeworkViewModel: ObservableObject {
    @Published var items: [HomeworkItem] = []
    @Published var total = 0
    @Published var counts = HomeworkCounts()
    @Published var cacheInfo = ""
    @Published var status = HomeworkStatusFilter.alle
    @Published var query = ""
    @Published var includeTests = false
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: APIError?
    @Published var pendingIDs: Set<String> = []
    @Published var canLoadMore = false

    private let service: HomeworkService
    private var searchTask: Task<Void, Never>?
    private static let pageSize = 50

    init(service: HomeworkService) {
        self.service = service
    }

    func refresh() async {
        isLoading = true
        self.error = nil
        do {
            let page = try await service.list(status: status, includeTests: includeTests,
                                              q: query, limit: Self.pageSize, offset: 0,
                                              refresh: true)
            apply(page: page)
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    func loadFromCache() async {
        do {
            let page = try await service.list(status: status, includeTests: includeTests,
                                              q: query, limit: Self.pageSize, offset: 0)
            apply(page: page)
            self.error = nil
        } catch let e as APIError {
            self.error = e
            isLoading = false
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
            isLoading = false
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        do {
            let page = try await service.list(status: status, includeTests: includeTests,
                                              q: query, limit: Self.pageSize,
                                              offset: items.count)
            items += page.items
            total = page.total
            counts = page.counts ?? counts
            canLoadMore = items.count < page.total
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoadingMore = false
    }

    private func apply(page: HomeworkListResponse) {
        items = page.items
        total = page.total
        counts = page.counts ?? HomeworkCounts()
        cacheInfo = page.cacheInfo ?? ""
        isLoading = false
        canLoadMore = page.items.count < page.total
    }

    func onStatus(_ status: String) async {
        guard HomeworkStatusFilter.all.contains(status), status != self.status else { return }
        self.status = status
        isLoading = true
        self.error = nil
        await loadFromCache()
    }

    func onQuery(_ query: String) {
        self.query = query
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await loadFromCache()
        }
    }

    func onIncludeTests(_ include: Bool) async {
        guard include != includeTests else { return }
        includeTests = include
        isLoading = true
        await loadFromCache()
    }

    /// Erledigt-Schalter (links wischen im Web = dieser Aufruf).
    func toggleDone(_ item: HomeworkItem) async {
        let id = item.uid
        guard !pendingIDs.contains(id) else { return }
        pendingIDs.insert(id)
        self.error = nil
        do {
            let updated = try await service.setDone(id: id, done: !(item.isDone ?? false))
            items = items.map { $0.uid == id ? updated : $0 }
            pendingIDs.remove(id)
            await silentRecount()
        } catch let e as APIError {
            self.error = e
            pendingIDs.remove(id)
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
            pendingIDs.remove(id)
        }
    }

    /// Papierkorb: hineinlegen bzw. zurückholen (Zurückholen markiert
    /// serverseitig gleichzeitig als offen, wie im Web).
    func toggleTrash(_ item: HomeworkItem) async {
        let id = item.uid
        guard !pendingIDs.contains(id) else { return }
        pendingIDs.insert(id)
        self.error = nil
        do {
            let updated = try await service.setTrash(id: id, hide: !(item.isHidden ?? false))
            if status == HomeworkStatusFilter.papierkorb, updated.isHidden == false {
                items = items.filter { $0.uid != id }
            } else {
                items = items.map { $0.uid == id ? updated : $0 }
            }
            total = items.count
            pendingIDs.remove(id)
            await silentRecount()
        } catch let e as APIError {
            self.error = e
            pendingIDs.remove(id)
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
            pendingIDs.remove(id)
        }
    }

    private func silentRecount() async {
        do {
            let page = try await service.list(status: status, includeTests: includeTests,
                                              q: query, limit: Self.pageSize, offset: 0)
            counts = page.counts ?? counts
            total = page.total
        } catch {
            // Zähler bleiben beim alten Stand (still, ohne Spinner).
        }
    }
}
