import Foundation

/// Eingefrorene Ziele (Paket 0, eingefroren — Pakete A bis D hängen hier an).
///
/// Die Thread-Route trägt die Nachricht als Wert mit (kein Extraload,
/// kein geteiltes ViewModel). Die Zwei-Faktor-Route trägt das
/// Zwischen-Token aus der Login-Antwort.
public enum Route: Hashable, Sendable {
    case login
    case twoFA(pending: String)
    case overview
    case messages
    case thread(message: MessageHeader)
    case compose
    case homework
    case timetable
    case school
    case grades
    case settings
    case devices
}

// MARK: - Topbar-Bereiche (Paket F)
//
// Die `Route`-Aufzählung oben bleibt eingefroren; diese Typen mappen nur
// darauf. Die Topbar zeigt `TopBarConfig.visible` in gespeicherter
// Reihenfolge. Termine (`.school`) sind defaultmäßig kein fester Reiter,
// bleiben aber erreichbar (Profilmenü, Übersicht, Editor). Einstellungen und
// Geräte sind keine Reiter (nur Profilmenü). Auswahl und Reihenfolge liegen
// in den UserDefaults (`storageKey`) wie Akzent und Basis-URL; Änderungen
// melden `topBarConfigDidChange`.

public extension Notification.Name {
    static let topBarConfigDidChange = Notification.Name("de.eduflow.topBarConfigDidChange")
}

/// Wählbarer Topbar-Bereich (reine Werte, testbar).
public enum TopBarSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case messages
    case homework
    case grades
    case timetable
    case school

    public var id: String { rawValue }

    public var route: Route {
        switch self {
        case .overview: return .overview
        case .messages: return .messages
        case .homework: return .homework
        case .grades: return .grades
        case .timetable: return .timetable
        case .school: return .school
        }
    }

    /// Reiter-Titel (Absicht: gleiche Literale wie bisher, damit der
    /// String-Katalog unverändert weiter greift).
    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .messages: return "Messages"
        case .homework: return "Homework"
        case .grades: return "Grades"
        case .timetable: return "Timetable"
        case .school: return "Events"
        }
    }

    /// SF-Symbol des Reiters (nur Gestaltung, nicht übersetzt).
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .messages: return "envelope"
        case .homework: return "checklist"
        case .grades: return "chart.bar"
        case .timetable: return "calendar"
        case .school: return "sparkles"
        }
    }
}

/// Auswahl und Reihenfolge der Topbar (UserDefaults, testbar).
public enum TopBarConfig {
    public static let storageKey = "de.eduflow.topBarSections"

    /// Standard: ohne Termine (bleiben anderswo erreichbar).
    public static let defaultVisible: [TopBarSection] = [
        .overview, .messages, .homework, .grades, .timetable,
    ]

    /// Sichtbare Bereiche in Reihenfolge (unbekannte/leere Stände fallen
    /// auf den Standard zurück, Duplikate entfallen).
    public static var visible: [TopBarSection] {
        sanitize(UserDefaults.standard.stringArray(forKey: storageKey))
    }

    public static func save(_ sections: [TopBarSection]) {
        UserDefaults.standard.set(sections.map(\.rawValue), forKey: storageKey)
        NotificationCenter.default.post(name: .topBarConfigDidChange, object: nil)
    }

    /// Rohe Ablage bereinigen (rein, testbar): unbekannte Codes raus,
    /// Duplikate raus, leer/fehlend → Standard.
    public static func sanitize(_ raw: [String]?) -> [TopBarSection] {
        guard let raw else { return defaultVisible }
        var seen = Set<String>()
        let cleaned = raw.compactMap { code -> TopBarSection? in
            guard !seen.contains(code), let section = TopBarSection(rawValue: code) else {
                return nil
            }
            seen.insert(code)
            return section
        }
        return cleaned.isEmpty ? defaultVisible : cleaned
    }

    /// Bereich umsortieren (rein, testbar; still bei ungültigem Index).
    public static func move(_ sections: [TopBarSection], from: Int, by offset: Int) -> [TopBarSection] {
        guard sections.indices.contains(from) else { return sections }
        let target = min(max(from + offset, 0), sections.count - 1)
        guard target != from else { return sections }
        var result = sections
        let item = result.remove(at: from)
        result.insert(item, at: target)
        return result
    }
}
