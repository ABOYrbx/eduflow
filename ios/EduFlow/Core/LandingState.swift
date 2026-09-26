import Combine
import Foundation

// MARK: - Start-Tab aus dem landing-Setting (wie Web-/ nach Login)
//
// GET /settings → landing (uebersicht/dashboard/hausaufgaben/noten/
// stundenplan, Fallback Übersicht). Reine Auswahl-Logik, kein neuer Client.

@MainActor
final class LandingState: ObservableObject {
    enum Tab: Hashable {
        case overview, homework, messages, timetable, more
    }

    @Published var selected: Tab = .overview

    private let service: SettingsService
    private var resolved = false

    init(service: SettingsService) {
        self.service = service
    }

    func resolve() async {
        guard !resolved else { return }
        resolved = true
        do {
            selected = Self.tab(for: try await service.load().1.landing)
        } catch {
            selected = .overview
        }
    }

    /// Reine Abbildung landing → Tab (offline testbar, ohne Netzwerk).
    /// Noten/Einstellungen leben im Mehr-Tab (Redesign-PNG).
    nonisolated static func tab(for landing: String) -> Tab {
        switch landing {
        case "dashboard": return .messages
        case "hausaufgaben": return .homework
        case "stundenplan": return .timetable
        case "noten": return .more
        default: return .overview
        }
    }
}
