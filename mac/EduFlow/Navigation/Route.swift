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
