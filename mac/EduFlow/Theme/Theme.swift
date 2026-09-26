import SwiftUI

/// Web-Palette 1:1 aus `static/uber.css` (`:root` + `[data-theme="dark"]`).
/// Aufruf mit dem aktuellen Farbschema aus der Umgebung.
public enum EduFlowPalette {
    public static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x00 / 255)
            : Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255)
    }

    public static func surface1(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255)
            : Color(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF6 / 255)
    }

    public static func surface2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255)
            : Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255)
    }

    public static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255)
            : Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x00 / 255)
    }

    public static func inkSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xED / 255, green: 0xED / 255, blue: 0xED / 255)
            : Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    }

    public static func inkMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0xA3 / 255)
            : Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255)
    }

    public static func inkDim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x73 / 255, green: 0x73 / 255, blue: 0x73 / 255)
            : Color(red: 0x9E / 255, green: 0x9E / 255, blue: 0x9E / 255)
    }

    public static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255)
            : Color(red: 0xE2 / 255, green: 0xE2 / 255, blue: 0xE2 / 255)
    }

    public static func borderSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)
            : Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255)
    }

    public static func borderStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x52 / 255, green: 0x52 / 255, blue: 0x52 / 255)
            : Color(red: 0xCF / 255, green: 0xCF / 255, blue: 0xCF / 255)
    }

    /// Karten-Grund (`#fff`, dark `#101010`).
    public static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255)
            : Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255)
    }

    /// Karten-Hover (`#FAFAFA`, dark `#161616`).
    public static func cardHover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255)
            : Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    }

    // MARK: - Statusfarben (modusübergreifend, wie `.tag-red` & Co.)

    public static let red = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
    public static let amber = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255)
    public static let blue = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
    public static let green = Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)

    /// Statusfarbe zur Hausaufgaben-Kante (`.hw.st-*`).
    public static func homeworkEdge(_ status: String, scheme: ColorScheme) -> Color {
        switch status {
        case HomeworkItemStatus.ueberfaellig: return red
        case HomeworkItemStatus.heute: return amber
        case HomeworkItemStatus.offen: return blue
        case HomeworkItemStatus.erledigt: return green
        default: return border(scheme)
        }
    }
}

/// Akzentfarben 1:1 zum Web (`static/uber.css`, acht Farben).
/// Hell und dunkel folgt dem System (SwiftUI-Standard).
public enum Accent: String, CaseIterable, Identifiable, Sendable {
    case black, blue, violet, teal, green, orange, red, pink

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .black: return NSLocalizedString("common_accent_black", value: "Schwarz", comment: "Akzentfarbe")
        case .blue: return NSLocalizedString("common_accent_blue", value: "Blau", comment: "Akzentfarbe")
        case .violet: return NSLocalizedString("common_accent_violet", value: "Violett", comment: "Akzentfarbe")
        case .teal: return NSLocalizedString("common_accent_teal", value: "Petrol", comment: "Akzentfarbe")
        case .green: return NSLocalizedString("common_accent_green", value: "Grün", comment: "Akzentfarbe")
        case .orange: return NSLocalizedString("common_accent_orange", value: "Orange", comment: "Akzentfarbe")
        case .red: return NSLocalizedString("common_accent_red", value: "Rot", comment: "Akzentfarbe")
        case .pink: return NSLocalizedString("common_accent_pink", value: "Pink", comment: "Akzentfarbe")
        }
    }

    /// Grundton wie im Web (`--accent`).
    public var color: Color {
        switch self {
        case .black: return Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x00 / 255)
        case .blue: return Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
        case .violet: return Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
        case .teal: return Color(red: 0x0E / 255, green: 0x74 / 255, blue: 0x90 / 255)
        case .green: return Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)
        case .orange: return Color(red: 0xEA / 255, green: 0x58 / 255, blue: 0x0C / 255)
        case .red: return Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
        case .pink: return Color(red: 0xDB / 255, green: 0x27 / 255, blue: 0x77 / 255)
        }
    }

    /// Hover-Ton (`--accent-hover`).
    public var hover: Color {
        switch self {
        case .black: return Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
        case .blue: return Color(red: 0x1D / 255, green: 0x4E / 255, blue: 0xD8 / 255)
        case .violet: return Color(red: 0x6D / 255, green: 0x28 / 255, blue: 0xD9 / 255)
        case .teal: return Color(red: 0x15 / 255, green: 0x5E / 255, blue: 0x75 / 255)
        case .green: return Color(red: 0x15 / 255, green: 0x80 / 255, blue: 0x3D / 255)
        case .orange: return Color(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255)
        case .red: return Color(red: 0xB9 / 255, green: 0x1C / 255, blue: 0x1C / 255)
        case .pink: return Color(red: 0xBE / 255, green: 0x18 / 255, blue: 0x5C / 255)
        }
    }

    /// Schrift auf Akzent (`--accent-ink`, immer Weiß).
    public var ink: Color {
        Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255)
    }

    /// Aufgelöste Knopf-Farbe: Schwarz folgt wie im Web-Standard dem
    /// Modus (Light schwarz, Dark weiß), Farben bleiben fix.
    public func resolved(_ scheme: ColorScheme) -> Color {
        if self == .black {
            return EduFlowPalette.ink(scheme)
        }
        return color
    }

    /// Aufgelöste Schrift auf Knopf (Schwarz im Dark Mode → schwarz).
    public func resolvedInk(_ scheme: ColorScheme) -> Color {
        if self == .black {
            return EduFlowPalette.canvas(scheme)
        }
        return ink
    }

    private static let storageKey = "de.eduflow.accent"

    /// Gespeicherte Wahl (fällt auf Schwarz wie im Web).
    public static var stored: Accent {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
            return Accent(rawValue: raw) ?? .black
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

/// Inter-Typografie wie im Web (`--font-ui`; gebündelt in Resources).
public enum UberFont {
    public static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter", size: size).weight(weight)
    }
}

// MARK: - Akzent in der Umgebung

/// Aktiver Akzent für Komponenten (Knöpfe, Tags, Eyebrow).
/// Die App setzt ihn einmalig aus der gespeicherten Wahl.
private struct UberAccentKey: EnvironmentKey {
    static let defaultValue: Accent = .black
}

public extension EnvironmentValues {
    var uberAccent: Accent {
        get { self[UberAccentKey.self] }
        set { self[UberAccentKey.self] = newValue }
    }
}

public extension View {
    func uberAccent(_ accent: Accent) -> some View {
        environment(\.uberAccent, accent)
    }
}
