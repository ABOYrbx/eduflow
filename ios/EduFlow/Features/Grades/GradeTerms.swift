import Foundation

// MARK: - Halbjahr-Tabs (Paket E, wie Web-noten() + Android Grades.kt)
//
// Halbjahr-Key "2025-H1" aus dem Notendatum (Schuljahr Sept–Aug),
// deutsche Bezeichnung („1. Halbjahr 25/26"), Tabs neuestes zuerst
// + „Gesamt". Reine Logik (offline testbar).

struct GradeTerm: Equatable {
    var key: String = "alle"
    var label: String = "Gesamt"
    var count: Int = 0
}

enum GradeTerms {
    /// Aktueller Halbjahr-Key (Schuljahr Sept–Aug, wie currentTermKey).
    static func currentKey(year: Int, month: Int) -> String {
        let sy = month >= 9 ? year : year - 1
        let half = (month >= 9 || month == 1) ? 1 : 2
        return "\(sy)-H\(half)"
    }

    /// Notendatum (YYYY-MM-DD) → Halbjahr-Key (wie gradeTermKey).
    static func key(for dateIso: String?, fallback: String) -> String {
        guard let iso = dateIso?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return fallback
        }
        let parts = iso.split(separator: "-")
        guard parts.count >= 3,
              let y = Int(parts[0]), let m = Int(parts[1]),
              (1...12).contains(m) else { return fallback }
        return currentKey(year: y, month: m)
    }

    /// Halbjahr-Key → deutsche Bezeichnung (wie gradeTermLabel).
    static func label(for key: String) -> String {
        let parts = key.split(separator: "-H")
        guard parts.count == 2,
              let sy = Int(parts[0]), let half = Int(parts[1]) else { return key }
        return "\(half). Halbjahr \(String(format: "%02d", sy % 100))/\(String(format: "%02d", (sy + 1) % 100))"
    }

    /// Halbjahre aus den geladenen Noten ableiten (neuestes zuerst) +
    /// „Gesamt" (wie buildGradeTerms).
    static func build(from items: [GradeItem], fallback: String) -> [GradeTerm] {
        var counts: [String: Int] = [:]
        for item in items {
            let k = key(for: item.dateIso, fallback: fallback)
            counts[k, default: 0] += 1
        }
        let terms = counts.sorted { $0.key > $1.key }.map { (k, c) in
            GradeTerm(key: k, label: label(for: k), count: c)
        }
        return terms + [GradeTerm(key: "alle", label: "Gesamt", count: items.count)]
    }

    /// Aktuelles Halbjahr aus dem Geräte-Datum (Fallback „alle").
    static var currentFallback: String {
        let cal = Calendar.current
        let now = Date()
        return currentKey(year: cal.component(.year, from: now),
                          month: cal.component(.month, from: now))
    }
}
