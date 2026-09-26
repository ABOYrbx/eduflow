import Foundation

/// Hausaufgabe 1:1 zum Web-Bauer (`app.py` `homework_to_dict`, plus
/// lokales `is_hidden` aus dem Papierkorb wie im Web).
public struct HomeworkDTO: Decodable, Sendable {
    public var id: Int = 0
    public var type: String = ""
    public var typeLabel: String = ""
    public var title: String = ""
    public var description: String = ""
    public var subject: String = ""
    public var author: String = ""
    public var recipient: String = ""
    public var assigned: String = ""
    public var assignedIso: String = ""
    public var due: String = ""
    public var dueDisplay: String = ""
    public var dueRaw: String = ""
    public var status: String = ""
    public var statusClass: String = ""
    public var tagClass: String = ""
    public var isDone: Bool = false
    public var doneAt: String = ""
    public var isStarred: Bool = false
    public var extra: String = ""
    public var isHidden: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        type = (try? box.decodeIfPresent(String.self, forKey: .type)) ?? ""
        typeLabel = (try? box.decodeIfPresent(String.self, forKey: .typeLabel)) ?? ""
        title = (try? box.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? box.decodeIfPresent(String.self, forKey: .description)) ?? ""
        subject = (try? box.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        author = (try? box.decodeIfPresent(String.self, forKey: .author)) ?? ""
        recipient = (try? box.decodeIfPresent(String.self, forKey: .recipient)) ?? ""
        assigned = (try? box.decodeIfPresent(String.self, forKey: .assigned)) ?? ""
        assignedIso = (try? box.decodeIfPresent(String.self, forKey: .assignedIso)) ?? ""
        due = (try? box.decodeIfPresent(String.self, forKey: .due)) ?? ""
        dueDisplay = (try? box.decodeIfPresent(String.self, forKey: .dueDisplay)) ?? ""
        dueRaw = (try? box.decodeIfPresent(String.self, forKey: .dueRaw)) ?? ""
        status = (try? box.decodeIfPresent(String.self, forKey: .status)) ?? ""
        statusClass = (try? box.decodeIfPresent(String.self, forKey: .statusClass)) ?? ""
        tagClass = (try? box.decodeIfPresent(String.self, forKey: .tagClass)) ?? ""
        isDone = (try? box.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        doneAt = (try? box.decodeIfPresent(String.self, forKey: .doneAt)) ?? ""
        isStarred = (try? box.decodeIfPresent(Bool.self, forKey: .isStarred)) ?? false
        extra = (try? box.decodeIfPresent(String.self, forKey: .extra)) ?? ""
        isHidden = (try? box.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, typeLabel, title, description, subject, author
        case recipient, assigned, assignedIso, due, dueDisplay, dueRaw
        case status, statusClass, tagClass, isDone, doneAt, isStarred
        case extra, isHidden
    }
}

/// Zähler wie im Web (`api/homework.py` `_build_view`).
/// ACHTUNG: JSON-Schlüssel ascii `ueberfaellig` (ohne Umlaut).
public struct HomeworkCounts: Decodable, Sendable {
    public var offen: Int = 0
    public var ueberfaellig: Int = 0
    public var erledigt: Int = 0
    public var papierkorb: Int = 0

    public init() {}
}

/// `GET /homework` → Hülle plus Zähler plus Cache-Info.
public struct HomeworkListResponse: Decodable, Sendable {
    public var items: [HomeworkDTO] = []
    public var total: Int = 0
    public var limit: Int = 50
    public var offset: Int = 0
    public var counts: HomeworkCounts?
    public var cacheInfo: String?

    public init() {}
}

/// Statusfilter wie Web plus API (`?status=...`).
public enum HomeworkStatusFilter {
    public static let alle = "alle"
    public static let offen = "offen"
    public static let ueberfaellig = "überfällig"
    public static let erledigt = "erledigt"
    public static let papierkorb = "papierkorb"

    public static let all = [alle, offen, ueberfaellig, erledigt, papierkorb]
}

/// Item-Statuswerte aus `homework_to_dict`.
public enum HomeworkItemStatus {
    public static let ueberfaellig = "überfällig"
    public static let heute = "heute fällig"
    public static let offen = "offen"
    public static let erledigt = "erledigt"
    public static let ohneDatum = "ohne Datum"
}
