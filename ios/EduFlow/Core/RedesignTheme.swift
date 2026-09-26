import SwiftUI
import UIKit

// MARK: - Redesign-Tokens aus templates/EduFlow · Weitere App Screens.png
//
// Paket 0, eingefroren. Light: grauer Hintergrund, weiße Karten.
// Dark: schwarz (System-Umschalter, kein eigener Schalter).

private func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    })
}

extension Color {
    /// Hintergrund (Light #F4F4F5 / Dark #000000).
    static var rBackground: Color { dynamic(0xF4F4F5, 0x000000) }
    /// Karte (Light #FFFFFF / Dark #161616).
    static var rCard: Color { dynamic(0xFFFFFF, 0x161616) }
    /// Karten-Rahmen (Light #E4E4E4 / Dark #262626).
    static var rCardBorder: Color { dynamic(0xE4E4E4, 0x262626) }
    /// Schrift (Light #111111 / Dark #FFFFFF).
    static var rInk: Color { dynamic(0x111111, 0xFFFFFF) }
    /// Sekundär-Text (Light #6E6E6E / Dark #A3A3A3).
    static var rMuted: Color { dynamic(0x6E6E6E, 0xA3A3A3) }
    /// Sekundär-Fläche (Light #ECECEE / Dark #262626).
    static var rSecondaryFill: Color { dynamic(0xECECEE, 0x262626) }
    /// Primär-Button (Light schwarz / Dark weiß, invertierte Schrift).
    static var rPrimary: Color { dynamic(0x000000, 0xFFFFFF) }
    static var rOnPrimary: Color { dynamic(0xFFFFFF, 0x000000) }
    /// Status-Dots (Aufgaben-Liste).
    static var rDotOrange: Color { Color(red: 0xE8 / 255, green: 0x93 / 255, blue: 0x0C / 255) }
    static var rDotRed: Color { Color(red: 0xD9 / 255, green: 0x2D / 255, blue: 0x20 / 255) }
    static var rDotBlue: Color { Color(red: 0x24 / 255, green: 0x70 / 255, blue: 0xE0 / 255) }
    static var rDotGreen: Color { Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255) }
}

// MARK: - Akzentfarben (Paket F/G, wie Web theme.js data-accent)
//
// 8 Farben wie Android (Color.kt Accents). Schwarz = Standard.
// Wie auf Android fließt der Akzent derzeit nur in die Dots-Auswahl
// (persistiert); das Theme bleibt schwarz/weiß (PNG).

struct AccentOption {
    let key: String
    let label: String
    let light: UInt32
    let dark: UInt32

    /// Swatch im Menü: Schwarz wird im Dark Mode weiß (wie Web/Android).
    func swatch(dark: Bool) -> Color {
        let hex = dark ? self.dark : light
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
    }
}

enum AccentOptions {
    static let all: [AccentOption] = [
        AccentOption(key: "black", label: "Schwarz", light: 0x000000, dark: 0xFFFFFF),
        AccentOption(key: "blue", label: "Blau", light: 0x2563EB, dark: 0x2563EB),
        AccentOption(key: "violet", label: "Lila", light: 0x7C3AED, dark: 0x7C3AED),
        AccentOption(key: "teal", label: "Petrol", light: 0x0E7490, dark: 0x0E7490),
        AccentOption(key: "green", label: "Grün", light: 0x16A34A, dark: 0x16A34A),
        AccentOption(key: "orange", label: "Orange", light: 0xEA580C, dark: 0xEA580C),
        AccentOption(key: "red", label: "Rot", light: 0xDC2626, dark: 0xDC2626),
        AccentOption(key: "pink", label: "Pink", light: 0xDB2777, dark: 0xDB2777),
    ]

    static var keys: [String] { all.map(\.key) }

    static func option(for key: String) -> AccentOption {
        all.first(where: { $0.key == key }) ?? all[0]
    }
}

// MARK: - Typografie (Systemschrift, wie im PNG)

enum RFont {
    /// Screen-Titel, 22 bold.
    static let screenTitle = Font.system(size: 22, weight: .bold)
    /// Untertitel, 13 secondary.
    static let subtitle = Font.system(size: 13, weight: .regular)
    /// Sektions-Label, 11 bold, uppercase, tracking.
    static let section = Font.system(size: 11, weight: .bold)
    /// Karten-Titel, 15 semibold.
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    /// Karten-Sub, 13 secondary.
    static let cardSub = Font.system(size: 13, weight: .regular)
    /// Status-Pill, 10 bold, uppercase.
    static let pill = Font.system(size: 10, weight: .bold)
    /// Primär-Button, 16 semibold.
    static let primaryButton = Font.system(size: 16, weight: .semibold)
}
