import Foundation

/// Nachricht 1:1 zum Web-Bauer (`app.py` `event_to_dict`).
public struct MessageDTO: Decodable, Sendable {
    public var id: Int = 0
    public var timestamp: String = ""
    public var timestampIso: String = ""
    public var sortKey: String = ""
    public var author: String = ""
    public var recipient: String = ""
    public var type: String = ""
    public var typeLabel: String = ""
    public var text: String = ""
    public var isStarred: Bool = false
    public var isDone: Bool = false
    public var reactionCount: Int = 0
    public var extra: String = ""
    public var attachments: [MessageAttachment] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        timestamp = (try? box.decodeIfPresent(String.self, forKey: .timestamp)) ?? ""
        timestampIso = (try? box.decodeIfPresent(String.self, forKey: .timestampIso)) ?? ""
        sortKey = (try? box.decodeIfPresent(String.self, forKey: .sortKey)) ?? ""
        author = (try? box.decodeIfPresent(String.self, forKey: .author)) ?? ""
        recipient = (try? box.decodeIfPresent(String.self, forKey: .recipient)) ?? ""
        type = (try? box.decodeIfPresent(String.self, forKey: .type)) ?? ""
        typeLabel = (try? box.decodeIfPresent(String.self, forKey: .typeLabel)) ?? ""
        text = (try? box.decodeIfPresent(String.self, forKey: .text)) ?? ""
        isStarred = (try? box.decodeIfPresent(Bool.self, forKey: .isStarred)) ?? false
        isDone = (try? box.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        reactionCount = (try? box.decodeIfPresent(Int.self, forKey: .reactionCount)) ?? 0
        extra = (try? box.decodeIfPresent(String.self, forKey: .extra)) ?? ""
        attachments = (try? box.decodeIfPresent([MessageAttachment].self, forKey: .attachments)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, timestampIso, sortKey, author, recipient
        case type, typeLabel, text, isStarred, isDone, reactionCount
        case extra, attachments
    }

    /// Kopf für die Thread-Navigation (kein Extraload im Thread;
    /// Anhang-Downloads brauchen nur Kennung plus Index).
    public var header: MessageHeader {
        MessageHeader(
            id: id,
            author: author,
            text: text,
            timestamp: timestamp,
            attachmentNames: attachments.map(\.name)
        )
    }
}

/// Anhang 1:1 zum Web-Bauer (`{name, url}`).
public struct MessageAttachment: Decodable, Sendable {
    public var name: String = ""
    public var url: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? box.decodeIfPresent(String.self, forKey: .name)) ?? ""
        url = (try? box.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name, url
    }
}

/// Thread-Antwort (`api/messages.py` `_thread_payload`): Likes, Antworten,
/// Zusammenfassung plus Cache-Hinweis.
public struct ThreadResponse: Decodable, Sendable {
    public var likes: [ThreadLike] = []
    public var replies: [ThreadReply] = []
    public var replyIds: [String] = []
    public var summary: ThreadSummary = ThreadSummary()
    public var cached: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        likes = (try? box.decodeIfPresent([ThreadLike].self, forKey: .likes)) ?? []
        replies = (try? box.decodeIfPresent([ThreadReply].self, forKey: .replies)) ?? []
        if let strings = try? box.decodeIfPresent([String].self, forKey: .replyIds) {
            replyIds = strings
        } else if let ints = try? box.decodeIfPresent([Int].self, forKey: .replyIds) {
            replyIds = ints.map(String.init)
        } else {
            replyIds = []
        }
        summary = (try? box.decodeIfPresent(ThreadSummary.self, forKey: .summary)) ?? ThreadSummary()
        cached = (try? box.decodeIfPresent(Bool.self, forKey: .cached)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case likes, replies, replyIds, summary, cached
    }
}

public struct ThreadLike: Decodable, Sendable {
    public var name: String?
    public var date: String?

    public init() {}
}

public struct ThreadReply: Decodable, Sendable {
    public var name: String?
    public var date: String?
    public var text: String?

    public init() {}
}

public struct ThreadSummary: Decodable, Sendable {
    public var total: Int = 0
    public var likes: Int = 0
    public var replies: Int = 0
    public var seen: Int = 0

    public init() {}
}

/// Empfänger (`app.py` `get_recipients`: `{id, name, kind}`, nach Name).
public struct RecipientItem: Decodable, Sendable {
    public var id: String = ""
    public var name: String = ""
    public var kind: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? box.decodeIfPresent(String.self, forKey: .name)) ?? ""
        kind = (try? box.decodeIfPresent(String.self, forKey: .kind)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind
    }
}

/// `POST /messages/read` → `{marked}` (Server kennt kein
/// Ungelesen-Kennzeichen, Zähler aus Gesehen-Dateien wie im Web).
public struct MarkReadResult: Decodable, Sendable {
    public var marked: Int = 0

    public init() {}
}

/// `POST /messages/download-token` → `{download_token, expires_in}`
/// (kurzlebig, an Benutzer plus Datei gebunden).
public struct DownloadToken: Decodable, Sendable {
    public var downloadToken: String = ""
    public var expiresIn: Int = 0

    public init() {}
}

/// Nachrichtentypen mit deutschem Label (`app.py` `MESSAGE_TYPES`).
/// Leerer Typ bedeutet alle nachrichtenartigen Typen (Web-Default).
public enum MessageTypes {
    public static let alle = ""
    public static let sprava = "sprava"
    public static let news = "news"
    public static let anketa = "anketa"
    public static let chat = "chat"
    public static let genotif = "genotif"

    public static let all = [alle, sprava, news, anketa, chat, genotif]

    public static func label(_ type: String) -> String {
        switch type {
        case sprava: return NSLocalizedString("messages_type_sprava", value: "Nachricht", comment: "Nachrichtentyp")
        case news: return NSLocalizedString("messages_type_news", value: "Neuigkeit", comment: "Nachrichtentyp")
        case anketa: return NSLocalizedString("messages_type_anketa", value: "Umfrage", comment: "Nachrichtentyp")
        case chat: return NSLocalizedString("messages_type_chat", value: "Chat", comment: "Nachrichtentyp")
        case genotif: return NSLocalizedString("messages_type_genotif", value: "Mitteilung", comment: "Nachrichtentyp")
        default: return NSLocalizedString("messages_type_all", value: "Alle", comment: "Nachrichtentyp: alle")
        }
    }
}

/// Empfänger-ID-Format wie serverseitig (`app.py` `_RECIPIENT_ID_RE`).
/// Reine Logik (offline testbar, ohne Netzwerk).
public enum RecipientIDs {
    public static func isValid(_ id: String) -> Bool {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let pattern = "^(Teacher|Student|StudentOnly|Parent|Rodic|Ucitel)\\d+$"
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func clean(_ raw: [String]) -> [String] {
        var seen: [String] = []
        for entry in raw {
            let id = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, isValid(id), !seen.contains(id) {
                seen.append(id)
            }
        }
        return seen
    }
}
