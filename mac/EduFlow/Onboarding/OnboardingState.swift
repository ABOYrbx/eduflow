import Foundation

/// Onboarding-Zustand (reine Logik, ohne UI und ohne Netz, testbar).
///
/// Das Onboarding erscheint nur beim allerersten Start: keine Sitzung
/// und Flag noch nie gesetzt. Nach Abmelden geht es direkt zum Login.
public enum OnboardingState {
    public static let flagKey = "de.eduflow.onboardingCompletedV1"

    public static var completed: Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }

    public static func complete() {
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// Setzt die Einführung für einen erneuten Durchlauf zurück.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: flagKey)
    }

    public static func shouldShow(isLoggedIn: Bool) -> Bool {
        !isLoggedIn && !completed
    }

    /// Server-URL säubern wie die Login-Ansicht (leer → Default).
    public static func sanitizedBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TokenStore.defaultBaseURL : trimmed
    }
}
