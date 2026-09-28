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

/// Übersetzungsstand einer Sprache aus dem String-Katalog (Zähler =
/// Keys mit eigenem Wert, Nenner = Keys mit Übersetzungsbedarf; Deutsch
/// als Quelle zählt als vollständig). Per Skript aus
/// `mac/EduFlow/Resources/Localizable.xcstrings` erzeugt, siehe
/// `plaene/LOKALISIERUNG.md`.
public struct LocaleCoverage: Equatable, Sendable {
    public let code: String
    public let translated: Int
    public let total: Int
    public let percent: Int
}

/// Übersetzungsstand pro Sprache (manuell per Python aus dem Katalog
/// erzeugt; bei neuen Sprachen/Zahlen dort neu berechnen, siehe
/// `plaene/LOKALISIERUNG.md`).
public let localeCoverage: [LocaleCoverage] = [
    LocaleCoverage(code: "de", translated: 263, total: 263, percent: 100),
    LocaleCoverage(code: "en", translated: 263, total: 263, percent: 100),
    LocaleCoverage(code: "fr", translated: 238, total: 263, percent: 90),
    LocaleCoverage(code: "pl", translated: 238, total: 263, percent: 90),
    LocaleCoverage(code: "tr", translated: 238, total: 263, percent: 90),
]

/// App-Sprache als Override der Systemsprache (reine Logik, testbar).
///
/// Die Auswahl landet im System-Schlüssel `AppleLanguages` und wird beim
/// nächsten Start wirksam (Sandbox: kein Selbst-Neustart möglich).
/// `nil` heißt Systemsprache. Die Absicht steht zusätzlich unter eigenem
/// Schlüssel, weil `AppleLanguages` lesend immer auf die Systemsprache
/// zurückfällt und `nil` sonst nie unterscheidbar wäre.
public enum AppLanguage {
    private static let selectionKey = "de.eduflow.appLanguage"
    private static let systemKey = "AppleLanguages"

    /// Gespeicherte Wahl (`nil` = Systemsprache).
    public static var override: String? {
        UserDefaults.standard.string(forKey: selectionKey)
    }

    /// Wirksame Sprache: Override oder Systemsprache.
    public static var current: String {
        override ?? Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Sprachen aus dem String-Katalog (plus Systemsprache), sortiert.
    public static func available(excluding: Set<String> = []) -> [String] {
        let codes = Set(localeCoverage.map(\.code)).subtracting(excluding)
        return codes.sorted {
            nativeName($0).localizedCaseInsensitiveCompare(nativeName($1)) == .orderedAscending
        }
    }

    /// Eigenname der Sprache (`fr` → „français", Fallback: Code).
    public static func nativeName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }

    public static func set(_ code: String?) {
        if let code {
            UserDefaults.standard.set(code, forKey: selectionKey)
            UserDefaults.standard.set([code], forKey: systemKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectionKey)
            UserDefaults.standard.removeObject(forKey: systemKey)
        }
    }
}

/// Laufzeit-Erkennung der Katalog-Sprachen (reine Logik, testbar).
///
/// Liest die kompilierten `.strings`-Tabellen aus dem Bundle: Neue
/// Crowdin-Sprachen erscheinen damit automatisch — ohne Code-Änderung.
/// Kann eine Tabelle nicht gelesen werden, greift der Aufrufer auf die
/// statischen `localeCoverage`-Daten zurück.
public enum AppLocalizations {
    private static let table = "Localizable"
    private static let greetingKey = "onboarding_greeting"

    /// Zweibuchstabige Sprachcodes aus einer Bundle-Sprachliste filtern.
    public static func availableCodes(from localizations: [String]) -> [String] {
        localizations.filter {
            $0.range(of: "^[a-z]{2}$", options: .regularExpression) != nil
        }.sorted()
    }

    /// Sprachen mit lesbarer Tabelle aus dem Bundle.
    public static func availableCodes(in bundle: Bundle = .main) -> [String] {
        availableCodes(from: bundle.localizations).filter { table(for: $0, in: bundle) != nil }
    }

    /// `.strings`-Tabelle einer Sprache als Dict (nil wenn unlesbar).
    public static func table(for code: String, in bundle: Bundle = .main) -> [String: String]? {
        guard let url = bundle.url(forResource: table, withExtension: "strings", subdirectory: "\(code).lproj"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            return nil
        }
        return plist
    }

    /// Begrüßung für eine Sprache (nil wenn unübersetzt).
    public static func greeting(for code: String, in bundle: Bundle = .main) -> String? {
        guard let value = table(for: code, in: bundle)?[greetingKey], !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Begrüßungen für den Hallo-Zyklus (übersetzte zuerst via Bundle,
    /// Fallback wenn nichts lesbar ist).
    public static func greetings(fallback: [String], in bundle: Bundle = .main) -> [String] {
        let found = availableCodes(in: bundle).compactMap { greeting(for: $0, in: bundle) }
        return found.isEmpty ? fallback : found
    }

    /// Übersetzungsstand je Sprache aus den Tabellen (Nenner = Quell-Keys
    /// mit Bedarf, Zähler = davon Keys mit eigenem Wert; Quelle zählt voll).
    public static func coverage(sourceCode: String = "de", in bundle: Bundle = .main) -> [LocaleCoverage] {
        guard let source = table(for: sourceCode, in: bundle),
              let english = table(for: "en", in: bundle) else {
            return localeCoverage
        }
        let denominator = source.keys.filter { english[$0] != source[$0] }
        guard !denominator.isEmpty else { return localeCoverage }
        return availableCodes(in: bundle).map { code in
            if code == sourceCode {
                return LocaleCoverage(code: code, translated: denominator.count, total: denominator.count, percent: 100)
            }
            guard let target = table(for: code, in: bundle) else {
                return LocaleCoverage(code: code, translated: 0, total: denominator.count, percent: 0)
            }
            let done = denominator.filter { target[$0] != nil && target[$0] != source[$0] }
            let percent = Int((Double(done.count) / Double(denominator.count) * 100).rounded())
            return LocaleCoverage(code: code, translated: done.count, total: denominator.count, percent: percent)
        }
    }

    /// Zufallsreihenfolge ohne direkten Wiederholer am Rundenübergang.
    public static func shuffledCycle(count: Int, notStartingWith: Int?) -> [Int] {
        guard count > 0 else { return [] }
        var order = Array(0..<count).shuffled()
        if order.count > 1, let first = notStartingWith, order[0] == first {
            order.swapAt(0, 1)
        }
        return order
    }
}
