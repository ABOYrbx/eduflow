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
    /// Absender-Einschränkung (leer = alle). Wird clientseitig gefiltert,
    /// weil der Server keinen Absender-Parameter kennt.
    public var sender = ""
    public var isLoading = false
    /// Zeitpunkt der zuletzt geladenen Liste, falls sie aus dem lokalen
    /// Cache kam (Backend neu gestartet oder nicht erreichbar).
    public var cachedAt: Date?
    public var isLoadingMore = false
    public var error: APIError?
    public var markedMessage: String?
    public var seenIds: Set<Int> = []

    /// Wie viele Nachrichten breit geladen werden, wenn die Suche den Sender
    /// mit einbeziehen muss (Server kann nur Text suchen).
    public static let broadSearchLimit = 200
    /// Ab dieser Länge wird live gesucht; darunter bleibt die Liste, damit
    /// einzelne Tastenanschläge nicht schon filtern.
    public static let liveSearchMinLength = 3
    /// Wartezeit nach dem letzten Zeichen.
    public static let liveSearchDebounce: Duration = .milliseconds(300)

    private let store: TokenStore
    /// Optionaler Client für Tests (Stub-URL-Protokoll). Normal `nil`, dann
    /// baut der ViewModel den Client aus dem Store.
    private let clientOverride: APIClient?
    private var searchTask: Task<Void, Never>?

    public init(store: TokenStore, client: APIClient? = nil) {
        self.store = store
        self.clientOverride = client
        seenIds = Set(UserDefaults.standard.array(forKey: Self.seenKey) as? [Int] ?? [])
    }

    public var canLoadMore: Bool { items.count < total }

    /// Absender der geladenen Nachrichten, alphabetisch (für die Pille).
    public var senders: [String] {
        var seen = Set<String>()
        var found: [String] = []
        for message in items {
            let author = message.author.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !author.isEmpty, seen.insert(author).inserted else { continue }
            found.append(author)
        }
        return found.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Sichtbare Liste: Server-Treffer plus Absender- und Textfilter lokal.
    ///
    /// Der Server sucht nur im Text (`q`); Absender und ein Teil des Textes
    /// werden hier ergänzt, damit „Berger“ auch Nachrichten von Ms. Berger
    /// findet, deren Betreff den Namen nicht enthält.
    public var visibleItems: [MessageDTO] {
        let trimmedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSender.isEmpty else { return items }
        return items.filter { $0.author.localizedCaseInsensitiveCompare(trimmedSender) == .orderedSame }
    }

    /// Textsuche, die Sender mit einbezieht (für die lokale Ergänzung).
    public func matchesLocal(_ message: MessageDTO, needle: String) -> Bool {
        message.author.localizedCaseInsensitiveContains(needle)
            || message.text.localizedCaseInsensitiveContains(needle)
            || MessagePreview.subject(for: message).localizedCaseInsensitiveContains(needle)
    }

    /// Live-Suche mit Mindestlänge und Entprellung: kurze Eingaben (< 3
    /// Zeichen) zeigen wieder die ganze Liste, ohne Serverlast.
    public func searchLive(_ raw: String, onSessionExpired: @escaping () -> Void) async {
        searchTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < Self.liveSearchMinLength {
            guard query != "" || sender != "" else { return }
            query = ""
            sender = ""
            await load(onSessionExpired: onSessionExpired)
            return
        }
        // Erst ab der Mindestlänge als Server-Query übernehmen.
        query = trimmed
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.liveSearchDebounce)
            guard !Task.isCancelled else { return }
            guard let self, self.query == trimmed else { return }
            await self.load(onSessionExpired: onSessionExpired)
        }
    }

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
            let loaded = try await repo().list(
                type: type, query: query, offset: 0, refresh: refresh)
            let page = loaded.page
            cachedAt = loaded.savedAt
            items = page.items
            total = page.total
            // Absender- und Textfilter, die der Server nicht kann: erst
            // prüfen, ob der Server-Treffer schon passt, sonst breiter
            // laden und selbst filtern.
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !needle.isEmpty {
                let missing = page.items.filter { !matchesLocal($0, needle: needle) }
                if !missing.isEmpty {
                    let broad = try await repo().list(
                        type: type, query: "", limit: Self.broadSearchLimit, offset: 0)
                    items = broad.items.filter { matchesLocal($0, needle: needle) }
                    total = items.count
                }
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
        MessagesRepository(client: clientOverride ?? store.makeClient())
    }
}

/// Thread-Logik (Likes, Antworten, Antwort schreiben, Anhang laden).
@MainActor
@Observable
public final class ThreadViewModel {
    public var thread = ThreadResponse()
    public var isLoading = false
    /// Thread kam aus dem lokalen Cache (Backend neu gestartet oder weg).
    public var threadCachedAt: Date?
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
            let loaded = try await repo().thread(id: id, refresh: refresh)
            thread = loaded.response
            threadCachedAt = loaded.savedAt
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
    /// Empfängerliste kam aus dem lokalen Cache (nur lesbar, kein Senden).
    public var recipientsCachedAt: Date?

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
            recipientsCachedAt = page.savedAt
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
