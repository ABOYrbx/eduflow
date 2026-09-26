import Foundation

// MARK: - Nachrichten-Service (Paket B, nur gegen Paket 0)
//
// Parameter 1:1 wie die API (api/messages.py):
// since (YYYY-MM-DD, Standard 2000-01-01), type (Nachrichtentyp oder
// leer = alle), q (Textsuche, alle Wörter), limit (1..200), offset,
// refresh (0/1). Fehler via APIError.

final class MessagesService {
    private let client: () -> APIClient

    init(client: @escaping () -> APIClient) {
        self.client = client
    }

    func list(since: String? = nil, type: String = "", q: String = "",
              limit: Int = 50, offset: Int = 0,
              refresh: Bool = false) async throws -> Page<MessageItem> {
        var query: [String: String?] = [
            "type": type.isEmpty ? nil : type,
            "q": q.isEmpty ? nil : q,
            "limit": String(min(max(limit, 1), 200)),
            "offset": String(max(offset, 0)),
        ]
        if let since, !since.isEmpty { query["since"] = since }
        if refresh { query["refresh"] = "1" }
        return try await client().get("messages", query: query)
    }

    func thread(id: String, refresh: Bool = false) async throws -> ThreadResponse {
        var query: [String: String?] = [:]
        if refresh { query["refresh"] = "1" }
        return try await client().get("messages/\(id)/thread", query: query)
    }

    func markRead() async throws -> MarkReadResponse {
        try await client().post("messages/read", body: nil)
    }

    func recipients(limit: Int = 50, offset: Int = 0) async throws -> Page<RecipientItem> {
        try await client().get("recipients", query: [
            "limit": String(min(max(limit, 1), 200)),
            "offset": String(max(offset, 0)),
        ])
    }

    func send(recipients: [String], body: String) async throws -> MessageItem {
        try await client().post("messages/send", body: [
            "recipients": recipients,
            "body": body,
        ])
    }

    func reply(id: String, body: String) async throws -> ThreadResponse {
        try await client().post("messages/\(id)/reply", body: ["body": body])
    }

    /// Kurzzeit-Token für einen Anhang ausstellen (Bearer-Header, nie URL).
    /// Body {event_id, idx} → {download_token, expires_in}, wenige Minuten
    /// gültig und nur für genau diese Datei (api/messages.py).
    func downloadToken(eventID: String, index: Int) async throws -> DownloadTokenResponse {
        let eid: Any = Int(eventID) ?? eventID
        return try await client().post("messages/download-token",
                                       body: ["event_id": eid, "idx": index])
    }

    /// Download-URL für einen Anhang mit Kurzzeit-Token (`?dl=`).
    /// Das langlebige API-Token steht nie in der URL (kein Log-Eintrag
    /// serverseitig) — wie Android MessagesRepository.attachmentUrl.
    func attachmentDownloadURL(messageID: String, index: Int) async throws -> URL {
        let tok = try await downloadToken(eventID: messageID, index: index)
        guard !tok.downloadToken.isEmpty,
              let url = client().attachmentDownloadURL(
                messageID: messageID, index: index, dlToken: tok.downloadToken)
        else {
            throw APIError(code: "UPSTREAM",
                           message: APIError.message(for: "UPSTREAM"),
                           httpStatus: 0)
        }
        return url
    }
}

// MARK: - Reine Compose-Validierung (offline testbar, ohne Netzwerk)
//
// Wie serverseitig (api/messages.py): mind. 1 gültige Empfänger-ID,
// nicht-leerer Body (Server kürzt auf 5000 Zeichen).

enum MessageCompose {
    static func validate(recipients: [String], body: String) -> APIError? {
        if RecipientIDs.clean(recipients).isEmpty {
            return APIError(code: "VALIDATION",
                            message: "Bitte mindestens einen gültigen Empfänger wählen.",
                            httpStatus: 0)
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return APIError(code: "VALIDATION",
                            message: "Bitte einen Nachrichtentext eingeben.",
                            httpStatus: 0)
        }
        return nil
    }
}
