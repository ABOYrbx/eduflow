import Foundation

/// Nachrichten-Repository (Paket B, nur gegen Paket 0).
public struct MessagesRepository: Sendable {
    /// Verlauf-Standard wie im Web (`api/messages.py`, `EARLIEST_DEFAULT`).
    public static let defaultSince = "2000-01-01"
    public static let defaultLimit = 50

    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Nachrichtenliste (nur Top-Level, neueste zuerst). Filter heißen wie
    /// die Web-Parameter (`since`, `type`, `q`, `refresh`).
    public func list(
        since: String = defaultSince,
        type: String = MessageTypes.alle,
        query: String = "",
        limit: Int = defaultLimit,
        offset: Int = 0,
        refresh: Bool = false
    ) async throws -> CachedMessagePage {
        var items = [
            URLQueryItem(name: "since", value: since),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !type.isEmpty {
            items.append(URLQueryItem(name: "type", value: type))
        }
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.messages, query: items, as: Page<MessageDTO>.self
        )
        return CachedMessagePage(
            page: try APIClient.decode(Page<MessageDTO>.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Nachrichtenseite plus Zeitpunkt (nil = frisch vom Server).
    public struct CachedMessagePage: Sendable {
        public let page: Page<MessageDTO>
        public let savedAt: Date?

        public var items: [MessageDTO] { page.items }
        public var total: Int { page.total }
        public var limit: Int { page.limit }
        public var offset: Int { page.offset }
        public var isFromCache: Bool { savedAt != nil }
    }

    /// Thread (Likes, Antworten, Zusammenfassung plus Cache-Hinweis).
    public func thread(id: Int, refresh: Bool = false) async throws -> CachedThread {
        var items: [URLQueryItem] = []
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.thread(id), query: items, as: ThreadResponse.self
        )
        return CachedThread(
            response: try APIClient.decode(ThreadResponse.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Thread plus Zeitpunkt (nil = frisch vom Server).
    ///
    /// Leitet alle Felder durch, damit Aufrufer unverändert `.likes`,
    /// `.replies` und `.cached` lesen können — Letzteres kommt vom Server.
    public struct CachedThread: Sendable {
        public let response: ThreadResponse
        public let savedAt: Date?

        public var likes: [ThreadLike] { response.likes }
        public var replies: [ThreadReply] { response.replies }
        public var replyIds: [String] { response.replyIds }
        public var summary: ThreadSummary { response.summary }
        public var cached: Bool { response.cached }
        public var isFromLocalCache: Bool { savedAt != nil }
    }

    /// Alle aktuellen Nachrichten als gelesen markieren (meldet Zähler).
    @discardableResult
    public func markRead() async throws -> Int {
        let data = try await client.post(APIClient.Paths.markRead)
        return try APIClient.decode(MarkReadResult.self, from: data).marked
    }

    /// Empfänger (Lehrer plus Mitschüler, nach Name sortiert).
    public func recipients(
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> CachedRecipients {
        let items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        let payload = try await client.getCached(
            APIClient.Paths.recipients, query: items, as: Page<RecipientItem>.self
        )
        return CachedRecipients(
            page: try APIClient.decode(Page<RecipientItem>.self, from: payload.data),
            savedAt: payload.savedAt
        )
    }

    /// Empfängerliste plus Zeitpunkt (nil = frisch vom Server).
    public struct CachedRecipients: Sendable {
        public let page: Page<RecipientItem>
        public let savedAt: Date?

        public var items: [RecipientItem] { page.items }
        public var total: Int { page.total }
        public var isFromCache: Bool { savedAt != nil }
    }

    /// Senden (leere Empfänger oder leerer Text melden clientseitig
    /// Validierung; Antwort ist die neue Nachricht und erscheint sofort).
    /// IDs stammen aus der Server-Empfängerliste und werden dort erneut
    /// geprüft — hier nur leere/Doppelte entfernen, kein Format-Raten
    /// (dbi-Schlüssel sind nicht überall rein numerisch).
    @discardableResult
    public func send(recipients: [String], body: String) async throws -> MessageDTO {
        var seen: [String] = []
        for entry in recipients {
            let id = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !seen.contains(id) {
                seen.append(id)
            }
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seen.isEmpty, !text.isEmpty else {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
        let payload = try APIClient.jsonData([
            "recipients": seen,
            "body": text,
        ] as [String: Any])
        let data = try await client.post(APIClient.Paths.sendMessage, body: payload)
        return try APIClient.decode(MessageDTO.self, from: data)
    }

    /// Antworten (geht an alle im Thread; liefert den Thread frisch).
    @discardableResult
    public func reply(id: Int, body: String) async throws -> ThreadResponse {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw APIError(
                code: ErrorCodes.validation,
                message: APIError.englishFallback(for: ErrorCodes.validation)
            )
        }
        let payload = try APIClient.jsonData(["body": text])
        let data = try await client.post(APIClient.Paths.reply(id), body: payload)
        return try APIClient.decode(ThreadResponse.self, from: data)
    }

    /// Kurzzeit-Token für einen Anhang (empfohlen statt `?token=`).
    public func downloadToken(eventId: Int, index: Int) async throws -> DownloadToken {
        let payload = try APIClient.jsonData([
            "event_id": eventId,
            "idx": index,
        ] as [String: Any])
        let data = try await client.post(APIClient.Paths.downloadToken, body: payload)
        return try APIClient.decode(DownloadToken.self, from: data)
    }

    /// Anhang laden (authentifizierter Proxy, nur EduPage-Adressen
    /// serverseitig; Dateiname aus den Nachrichtendaten).
    /// Der Client-Download landet zuerst unter einem Temp-Namen; mit
    /// `filename` wird die Datei auf den bereinigten Originalnamen
    /// umbenannt (Teilen zeigt den echten Namen).
    public func downloadAttachment(eventId: Int, index: Int, filename: String? = nil) async throws -> URL {
        let token = try await downloadToken(eventId: eventId, index: index)
        let file = try await client.download(
            APIClient.Paths.attachment(eventId, index),
            query: [URLQueryItem(name: "dl", value: token.downloadToken)],
            useTokenQuery: false
        )
        let raw = (filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return file
        }
        let target = file.deletingLastPathComponent()
            .appendingPathComponent(Self.safeFilename(raw, index: index), isDirectory: false)
        guard target != file else {
            return file
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        do {
            try FileManager.default.moveItem(at: file, to: target)
            return target
        } catch {
            return file
        }
    }

    /// Dateiname bereinigen (keine Pfad-Trennzeichen, max. 120 Zeichen;
    /// Fallback nummeriert wie in der Ansicht).
    public static func safeFilename(_ name: String, index: Int) -> String {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["/", "\\", ":"] {
            clean = clean.replacingOccurrences(of: separator, with: "_")
        }
        clean = clean.filter { !$0.isNewline }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return "Datei \(index + 1)"
        }
        if clean.count > 120 {
            let prefix = String(clean.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
            clean = prefix.isEmpty ? "Datei \(index + 1)" : prefix
        }
        if clean == "." || clean == ".." {
            return "Datei \(index + 1)"
        }
        return clean
    }
}
