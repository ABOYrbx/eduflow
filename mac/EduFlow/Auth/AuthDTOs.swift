import Foundation

/// Anmelde-Antwort: `{status: ok, token, expires, subdomain, username}`
/// oder `{status: 2fa_required, pending_token, message}` (`api/auth.py`).
public struct LoginResponse: Decodable, Sendable {
    public var status: String = ""
    public var token: String?
    public var expires: String?
    public var subdomain: String?
    public var username: String?
    public var pendingToken: String?
    public var message: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? box.decodeIfPresent(String.self, forKey: .status)) ?? ""
        token = try? box.decodeIfPresent(String.self, forKey: .token)
        expires = try? box.decodeIfPresent(String.self, forKey: .expires)
        subdomain = try? box.decodeIfPresent(String.self, forKey: .subdomain)
        username = try? box.decodeIfPresent(String.self, forKey: .username)
        pendingToken = try? box.decodeIfPresent(String.self, forKey: .pendingToken)
        message = try? box.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case status, token, expires, subdomain, username
        case pendingToken
        case message
    }
}

/// Ergebnis der Anmeldung (gültig oder Zwei-Faktor-Pflicht).
public enum LoginResult: Equatable, Sendable {
    case loggedIn(token: String, expires: String, subdomain: String, username: String)
    case twoFaRequired(pendingToken: String, message: String)
}

/// Eigener Benutzer: `GET /me` → `{subdomain, username}`.
public struct MeInfo: Decodable, Sendable {
    public var subdomain: String = ""
    public var username: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        subdomain = (try? box.decodeIfPresent(String.self, forKey: .subdomain)) ?? ""
        username = (try? box.decodeIfPresent(String.self, forKey: .username)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case subdomain, username
    }
}

/// Ein Gerät: eigener Token-Datensatz ohne Secrets (`api/core.py`
/// `list_user_tokens`: `{id, short, device, created, expires}`).
public struct DeviceInfo: Decodable, Sendable {
    public var id: String = ""
    public var short: String = ""
    public var device: String = ""
    public var created: String = ""
    public var expires: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decodeIfPresent(String.self, forKey: .id)) ?? ""
        short = (try? box.decodeIfPresent(String.self, forKey: .short)) ?? ""
        device = (try? box.decodeIfPresent(String.self, forKey: .device)) ?? ""
        created = (try? box.decodeIfPresent(String.self, forKey: .created)) ?? ""
        expires = (try? box.decodeIfPresent(String.self, forKey: .expires)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, short, device, created, expires
    }
}

/// `GET /devices` → `{items, total}` (neueste zuerst, ohne Secrets).
public struct DevicesResponse: Decodable, Sendable {
    public var items: [DeviceInfo] = []
    public var total: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? box.decodeIfPresent([DeviceInfo].self, forKey: .items)) ?? []
        total = (try? box.decodeIfPresent(Int.self, forKey: .total)) ?? items.count
    }

    private enum CodingKeys: String, CodingKey {
        case items, total
    }
}

/// Status-Antwort `{status}` (Abmelden, Widerrufen).
public struct StatusResponse: Decodable, Sendable {
    public var status: String = "ok"

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? box.decodeIfPresent(String.self, forKey: .status)) ?? "ok"
    }

    private enum CodingKeys: String, CodingKey {
        case status
    }
}

/// Gemischter JSON-Wert (Schema-Defaults und Einstellungs-Werte sind skalar).
public enum SettingsValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() {
            self = .null
        } else if let value = try? box.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? box.decode(Int.self) {
            self = .int(value)
        } else if let value = try? box.decode(Double.self) {
            self = .double(value)
        } else if let value = try? box.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    public var bool: Bool {
        switch self {
        case .bool(let value): return value
        case .string(let value): return ["1", "true", "on"].contains(value.lowercased())
        case .int(let value): return value != 0
        default: return false
        }
    }
}

/// Ein Schema-Eintrag 1:1 zu `app.py` (`SETTINGS_SCHEMA`).
public struct SettingSpec: Decodable, Sendable {
    public var key: String = ""
    public var kind: String = "text"
    public var label: String = ""
    public var options: [[String]] = []
    public var defaultValue: SettingsValue?
    public var min: Int?
    public var max: Int?
    public var section: String?
    public var hint: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? box.decodeIfPresent(String.self, forKey: .key)) ?? ""
        kind = (try? box.decodeIfPresent(String.self, forKey: .kind)) ?? "text"
        label = (try? box.decodeIfPresent(String.self, forKey: .label)) ?? ""
        options = (try? box.decodeIfPresent([[String]].self, forKey: .options)) ?? []
        defaultValue = try? box.decodeIfPresent(SettingsValue.self, forKey: .defaultValue)
        min = try? box.decodeIfPresent(Int.self, forKey: .min)
        max = try? box.decodeIfPresent(Int.self, forKey: .max)
        section = try? box.decodeIfPresent(String.self, forKey: .section)
        hint = try? box.decodeIfPresent(String.self, forKey: .hint)
    }

    private enum CodingKeys: String, CodingKey {
        case key, kind, label, options, min, max, section, hint
        case defaultValue = "default"
    }
}

/// `GET /settings` → `{schema, values}`; `PUT /settings` → `{status, values}`
/// (Antwort ohne Schema wird toleriert).
public struct SettingsResponse: Decodable, Sendable {
    public var schema: [SettingSpec] = []
    public var values: [String: SettingsValue] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? box.decodeIfPresent([SettingSpec].self, forKey: .schema)) ?? []
        values = (try? box.decodeIfPresent([String: SettingsValue].self, forKey: .values)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case schema, values
    }
}

/// `POST /cache-clear` → `{status, cleared}` (Einstellungen bleiben erhalten).
public struct CacheClearResult: Decodable, Sendable {
    public var status: String = "ok"
    public var cleared: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? box.decodeIfPresent(String.self, forKey: .status)) ?? "ok"
        cleared = (try? box.decodeIfPresent(Int.self, forKey: .cleared)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case status, cleared
    }
}

/// Typisierte Sicht auf die Server-Werte (Parität mit `app.py`:
/// ungültige Werte fallen auf Defaults, Begrenzungen 1–50).
public struct SettingsValues: Equatable, Sendable {
    public var landing = "uebersicht"
    public var hwStatus = "alle"
    public var hwTests = false
    public var ovUnread = 10
    public var ovHomework = 10
    public var ovOrder = "messages,homework,weather,lunch"
    public var ovWetter = true
    public var wetterCity = ""

    public init() {}

    public static func from(_ values: [String: SettingsValue]) -> SettingsValues {
        var out = SettingsValues()
        let landings = ["uebersicht", "dashboard", "hausaufgaben", "noten", "stundenplan"]
        if let raw = values["landing"]?.string, landings.contains(raw) {
            out.landing = raw
        }
        let statuses = ["alle", "offen", "überfällig", "erledigt", "papierkorb"]
        if let raw = values["hw_status"]?.string, statuses.contains(raw) {
            out.hwStatus = raw
        }
        if let raw = values["hw_tests"] {
            out.hwTests = raw.bool
        }
        if let raw = values["ov_unread"]?.int {
            out.ovUnread = min(max(raw, 1), 50)
        }
        if let raw = values["ov_homework"]?.int {
            out.ovHomework = min(max(raw, 1), 50)
        }
        if let raw = values["ov_order"]?.string {
            let valid = ["messages", "homework", "weather", "lunch"]
            let parsed = raw.split(separator: ",").map(String.init).filter { valid.contains($0) }
            out.ovOrder = (parsed + valid.filter { !parsed.contains($0) }).joined(separator: ",")
        }
        if let raw = values["ov_wetter"] {
            out.ovWetter = raw.bool
        }
        if let raw = values["wetter_city"]?.string {
            out.wetterCity = raw
        }
        return out
    }

    /// Startseite nach Anmeldung (wie Web `/`: eingestellte Startseite).
    public func landingRoute() -> Route {
        switch landing {
        case "dashboard": return .messages
        case "hausaufgaben": return .homework
        case "noten": return .grades
        case "stundenplan": return .timetable
        default: return .overview
        }
    }
}
