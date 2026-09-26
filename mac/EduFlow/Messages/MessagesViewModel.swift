import Foundation

/// Listen-Logik (Filter, Suche, Paginierung, Aktualisieren, Gelesen).
@MainActor
@Observable
public final class MessagesViewModel {
    public var items: [MessageDTO] = []
    public var total: Int = 0
    public var type = MessageTypes.alle
    public var query = ""
    public var isLoading = false
    public var isLoadingMore = false
    public var error: APIError?
    public var markedMessage: String?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public var canLoadMore: Bool { items.count < total }

    public func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        markedMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repo().list(
                type: type, query: query, offset: 0, refresh: refresh)
            items = page.items
            total = page.total
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
            let page = try await repo().list(
                type: type, query: query, offset: items.count)
            items += page.items
            total = page.total
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

    public func markAllRead(onSessionExpired: () -> Void) async {
        error = nil
        markedMessage = nil
        do {
            let marked = try await repo().markRead()
            markedMessage = "\(marked) als gelesen markiert."
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

    private func repo() -> MessagesRepository {
        MessagesRepository(client: store.makeClient())
    }
}

/// Thread-Logik (Likes, Antworten, Antwort schreiben, Anhang laden).
@MainActor
@Observable
public final class ThreadViewModel {
    public var thread = ThreadResponse()
    public var isLoading = false
    public var isReplying = false
    public var replyText = ""
    public var error: APIError?
    public var downloadingIndex: Int?
    public var downloadedFile: URL?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public func load(id: Int, refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            thread = try await repo().thread(id: id, refresh: refresh)
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

    public func sendReply(id: Int, onSessionExpired: () -> Void) async {
        isReplying = true
        error = nil
        defer { isReplying = false }
        do {
            thread = try await repo().reply(id: id, body: replyText)
            replyText = ""
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

    public func download(eventId: Int, index: Int, onSessionExpired: () -> Void) async {
        downloadingIndex = index
        error = nil
        downloadedFile = nil
        defer { downloadingIndex = nil }
        do {
            downloadedFile = try await repo().downloadAttachment(eventId: eventId, index: index)
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

    private func repo() -> MessagesRepository {
        MessagesRepository(client: store.makeClient())
    }
}

/// Verfassen-Logik (Empfängersuche, Auswahl, Senden).
@MainActor
@Observable
public final class ComposeViewModel {
    public var recipients: [RecipientItem] = []
    public var search = ""
    public var selected: Set<String> = []
    public var body = ""
    public var isLoading = false
    public var isSending = false
    public var error: APIError?

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    public var filtered: [RecipientItem] {
        guard !search.isEmpty else { return recipients }
        let needle = search.lowercased()
        return recipients.filter { $0.name.lowercased().contains(needle) }
    }

    public var canSend: Bool {
        !selected.isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
    }

    public func load(onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            recipients = try await repo().recipients().items
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

    public func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    public func send(onSessionExpired: () -> Void) async -> Bool {
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            _ = try await repo().send(recipients: Array(selected), body: body)
            return true
        } catch let apiError as APIError {
            if SessionRecovery.forceLogout(error: apiError, isLoggedIn: store.isLoggedIn) {
                store.clear()
                onSessionExpired()
            } else {
                self.error = apiError
            }
            return false
        } catch {
            self.error = APIError(
                code: ErrorCodes.upstream,
                message: APIError.germanFallback(for: ErrorCodes.upstream)
            )
            return false
        }
    }

    private func repo() -> MessagesRepository {
        MessagesRepository(client: store.makeClient())
    }
}
