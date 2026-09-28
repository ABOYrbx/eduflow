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
    ) async throws -> Page<MessageDTO> {
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
        let data = try await client.get(APIClient.Paths.messages, query: items)
        return try APIClient.decode(Page<MessageDTO>.self, from: data)
    }

    /// Thread (Likes, Antworten, Zusammenfassung plus Cache-Hinweis).
    public func thread(id: Int, refresh: Bool = false) async throws -> ThreadResponse {
        var items: [URLQueryItem] = []
        if refresh {
            items.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let data = try await client.get(APIClient.Paths.thread(id), query: items)
        return try APIClient.decode(ThreadResponse.self, from: data)
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
    ) async throws -> Page<RecipientItem> {
        let items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        let data = try await client.get(APIClient.Paths.recipients, query: items)
        return try APIClient.decode(Page<RecipientItem>.self, from: data)
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
                message: APIError.germanFallback(for: ErrorCodes.validation)
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
                message: APIError.germanFallback(for: ErrorCodes.validation)
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
    public func downloadAttachment(eventId: Int, index: Int) async throws -> URL {
        let token = try await downloadToken(eventId: eventId, index: index)
        return try await client.download(
            APIClient.Paths.attachment(eventId, index),
            query: [URLQueryItem(name: "dl", value: token.downloadToken)],
            useTokenQuery: false
        )
    }
}
