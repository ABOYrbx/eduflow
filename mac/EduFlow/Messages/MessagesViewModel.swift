import Foundation

/// Reine Ableitung von Betreff und Vorschau aus dem Nachrichtentext.
///
/// Die API liefert kein Betreff-Feld (vgl. Android `bodyLine()`):
/// Betreff = erste nicht-leere Zeile (max. 80 Zeichen + …),
/// Vorschau = restliche Zeilen einzeilig normalisiert (max. 220 + …).
/// Fällt der Text aus, greift das Typ-Label, sonst „Nachricht“.
public enum MessagePreview: Sendable {
    public static let subjectMax = 80
    public static let previewMax = 220

    public static func subject(for message: MessageDTO) -> String {
        if let first = firstLine(of: message.text) {
            return first
        }
        let typeLabel = message.typeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typeLabel.isEmpty {
            return typeLabel
        }
        let type = message.type.trimmingCharacters(in: .whitespacesAndNewlines)
        if !type.isEmpty {
            let label = MessageTypes.label(type)
            // Unbekannte Typen fallen auf „Alle“ zurück — das ist kein Betreff.
            if label != MessageTypes.label(MessageTypes.alle) {
                return label
            }
        }
        return NSLocalizedString("messages_type_sprava", value: "Message", comment: "Nachrichten: Fallback-Betreff")
    }

    public static func preview(for message: MessageDTO) -> String {
        var rest: [String] = []
        var skippedFirst = false
        for raw in message.text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if !skippedFirst {
                skippedFirst = true
                continue
            }
            rest.append(line)
        }
        let flat = rest.joined(separator: " ")
        guard !flat.isEmpty else {
            return ""
        }
        if flat.count <= previewMax {
            return flat
        }
        return String(flat.prefix(previewMax))
            .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func firstLine(of text: String) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if line.count <= subjectMax {
                return line
            }
            return String(line.prefix(subjectMax))
                .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return nil
    }
}

/// Listen-Logik (Filter, Suche, Paginierung, Aktualisieren, Gelesen).
///
/// „Ungelesen“ ist lokal (gesehene IDs in den UserDefaults), weil der
/// Server kein Ungelesen-Kennzeichen führt (wie im Web über Gesehen-Dateien
/// und in Android über `seenMessagesFlow`): Thread-Öffnen markiert sofort
/// als gesehen, „Alle als gelesen“ übernimmt zusätzlich alle sichtbaren IDs.
@MainActor
@Observable
public final class MessagesViewModel {
    private static let seenKey = "de.eduflow.seenMessages"

    public var items: [MessageDTO] = []
    public var total: Int = 0
    public var type = MessageTypes.alle
    public var query = ""
    public var isLoading = false
    public var isLoadingMore = false
    public var error: APIError?
    public var markedMessage: String?
    public var seenIds: Set<Int> = []

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
        seenIds = Set(UserDefaults.standard.array(forKey: Self.seenKey) as? [Int] ?? [])
    }

    public var canLoadMore: Bool { items.count < total }

    public func isUnread(_ message: MessageDTO) -> Bool {
        !seenIds.contains(message.id)
    }

    public var unreadCount: Int {
        items.filter { !seenIds.contains($0.id) }.count
    }

    public func markSeen(_ id: Int) {
        guard seenIds.insert(id).inserted else {
            return
        }
        persistSeen()
    }

    private func persistSeen() {
        UserDefaults.standard.set(Array(seenIds), forKey: Self.seenKey)
    }

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
                message: APIError.englishFallback(for: ErrorCodes.upstream)
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
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
    }

    public func markAllRead(onSessionExpired: () -> Void) async {
        error = nil
        markedMessage = nil
        do {
            let marked = try await repo().markRead()
            markedMessage = String(format: NSLocalizedString("messages_marked_read", value: "%d marked as read.", comment: "Nachrichten: als gelesen markiert"), marked)
            seenIds.formUnion(items.map(\.id))
            persistSeen()
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
                message: APIError.englishFallback(for: ErrorCodes.upstream)
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
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
        }
    }

    public func download(eventId: Int, index: Int, filename: String? = nil, onSessionExpired: () -> Void) async {
        downloadingIndex = index
        error = nil
        downloadedFile = nil
        defer { downloadingIndex = nil }
        do {
            downloadedFile = try await repo().downloadAttachment(eventId: eventId, index: index, filename: filename)
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

    private func repo() -> MessagesRepository {
        MessagesRepository(client: store.makeClient())
    }
}

/// Verfassen-Logik (Empfängersuche, Auswahl, Senden).
@MainActor
@Observable
public final class ComposeViewModel {
    public var recipients: [RecipientItem] = []
    public var recipientTotal = 0
    public var search = ""
    public var selected: Set<String> = []
    public var body = ""
    public var isLoading = false
    public var isLoadingMoreRecipients = false
    public var isSending = false
    public var error: APIError?

    private static let recipientPageSize = 200

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

    public var canLoadMoreRecipients: Bool { recipients.count < recipientTotal }

    public func load(onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await repo().recipients(limit: Self.recipientPageSize)
            recipients = page.items
            recipientTotal = page.total
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

    public func loadMoreRecipients(onSessionExpired: () -> Void) async {
        guard canLoadMoreRecipients, !isLoadingMoreRecipients else { return }
        isLoadingMoreRecipients = true
        defer { isLoadingMoreRecipients = false }
        do {
            let page = try await repo().recipients(limit: Self.recipientPageSize, offset: recipients.count)
            recipients += page.items
            recipientTotal = page.total
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
                message: APIError.englishFallback(for: ErrorCodes.upstream)
            )
            return false
        }
    }

    private func repo() -> MessagesRepository {
        MessagesRepository(client: store.makeClient())
    }
}
