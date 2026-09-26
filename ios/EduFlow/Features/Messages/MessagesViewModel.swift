import Combine
import Foundation

// MARK: - Nachrichten-ViewModels (Paket B)
//
// Liste mit Typfilter, Suche (debounced), Refresh; Paginierung
// (limit 50, Mehr laden via offset); Alle-als-gelesen pflegt nur den
// Zähler (Server kennt kein Ungelesen-Flag, wie im Web via seen-Dateien).

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var items: [MessageItem] = []
    @Published var total = 0
    @Published var filter = MsgFilter.alle
    @Published var query = ""
    @Published var seenIDs: Set<String> = []
    @Published var marked = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: APIError?
    @Published var canLoadMore = false

    private let service: MessagesService
    private var searchTask: Task<Void, Never>?
    private static let pageSize = 50
    private static let seenKey = "eduflow.seenMessages"

    /// Clientseitige Filterung (Alle/Ungelesen/Mit Dateien, wie im PNG).
    var visibleItems: [MessageItem] {
        switch filter {
        case .ungelesen: return items.filter { !seenIDs.contains($0.uid) }
        case .mitDateien: return items.filter { !($0.attachments ?? []).isEmpty }
        case .alle: return items
        }
    }

    init(service: MessagesService) {
        self.service = service
        syncSeen()
    }

    /// Gesehene IDs aus UserDefaults laden (Server kennt kein
    /// Ungelesen-Flag — „Ungelesen" ist lokal, wie Android).
    func syncSeen() {
        seenIDs = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    private func persistSeen(_ ids: Set<String>) {
        seenIDs = Set(ids.suffix(2000))
        UserDefaults.standard.set(Array(seenIDs), forKey: Self.seenKey)
    }

    /// Thread-Öffnen markiert die Nachricht lokal als gesehen.
    func openThread(_ id: String) {
        persistSeen(seenIDs.union([id]))
    }

    func onFilter(_ filter: MsgFilter) {
        self.filter = filter
    }

    func refresh() async {
        isLoading = true
        self.error = nil
        syncSeen()
        do {
            let page = try await service.list(type: MessageTypes.alle, q: query,
                                              limit: Self.pageSize, offset: 0,
                                              refresh: true)
            items = page.items
            total = page.total
            canLoadMore = page.items.count < page.total
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    func loadFromCache() async {
        do {
            let page = try await service.list(type: MessageTypes.alle, q: query,
                                              limit: Self.pageSize, offset: 0)
            items = page.items
            total = page.total
            isLoading = false
            self.error = nil
            canLoadMore = page.items.count < page.total
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
            let page = try await service.list(type: MessageTypes.alle, q: query,
                                              limit: Self.pageSize,
                                              offset: items.count)
            items += page.items
            total = page.total
            canLoadMore = items.count < page.total
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoadingMore = false
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

    func markRead() async {
        do {
            marked = try await service.markRead().marked
            persistSeen(seenIDs.union(items.map(\.uid)))
            self.error = nil
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
    }
}

// MARK: - Thread (Likes, Antworten, Antwort schreiben)

@MainActor
final class ThreadViewModel: ObservableObject {
    @Published var thread: ThreadResponse?
    @Published var replyBody = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var error: APIError?

    private let service: MessagesService
    private let messageID: String

    init(service: MessagesService, messageID: String) {
        self.service = service
        self.messageID = messageID
    }

    /// Antwort geht an alle im Thread (wie Web: recipient="" serverseitig).
    func refresh() async {
        isLoading = true
        self.error = nil
        do {
            thread = try await service.thread(id: messageID, refresh: true)
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    func sendReply() async {
        let body = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        self.error = nil
        do {
            thread = try await service.reply(id: messageID, body: body)
            replyBody = ""
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isSending = false
    }
}

// MARK: - Verfassen (Empfänger + Text)

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var recipients: [RecipientItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var body = ""
    @Published var isLoadingRecipients = false
    @Published var isSending = false
    @Published var sentID: String?
    @Published var error: APIError?

    private let service: MessagesService

    init(service: MessagesService) {
        self.service = service
    }

    func loadRecipients() async {
        isLoadingRecipients = true
        self.error = nil
        do {
            recipients = try await service.recipients(limit: 200).items
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoadingRecipients = false
    }

    func toggleRecipient(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func send() async {
        let ids = RecipientIDs.clean(Array(selectedIDs))
        if let err = MessageCompose.validate(recipients: ids, body: body) {
            self.error = err
            return
        }
        guard !isSending else { return }
        isSending = true
        self.error = nil
        do {
            sentID = try await service.send(recipients: ids, body: body.trimmingCharacters(in: .whitespacesAndNewlines)).uid
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isSending = false
    }
}
