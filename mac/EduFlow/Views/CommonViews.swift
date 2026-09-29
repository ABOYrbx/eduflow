import AppKit
import SwiftUI

// MARK: - Knöpfe (`.btn`, volle Pillen-Geometrie)

///
/// Primär = Akzent, Hell = Karte mit starkem Rahmen, Klein = kompakt,
/// Erfolg/Fehler = kompakt mit Statusfarbe und weißer Schrift.
public enum PillStyle {
    case primary
    case light
    case smallPrimary
    case smallLight
    case smallSuccess
    case smallError
}

public struct UberButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    public let style: PillStyle

    public init(_ style: PillStyle = .primary) {
        self.style = style
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UberFont.text(14, weight: .bold))
            .padding(.vertical, style == .primary || style == .light ? 13 : 12)
            .padding(.horizontal, style == .primary || style == .light ? 22 : 20)
            .frame(maxWidth: style == .primary || style == .light ? .infinity : nil)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var backgroundColor: Color {
        if style == .primary || style == .smallPrimary {
            accent.resolved(scheme)
        } else if style == .smallSuccess {
            EduFlowPalette.green
        } else if style == .smallError {
            EduFlowPalette.red
        } else {
            EduFlowPalette.card(scheme)
        }
    }

    private var foregroundColor: Color {
        if style == .primary || style == .smallPrimary {
            accent.resolvedInk(scheme)
        } else if style == .smallSuccess || style == .smallError {
            Color.white
        } else {
            EduFlowPalette.ink(scheme)
        }
    }
}

private struct UberLightBorder: ViewModifier {
    @Environment(\.colorScheme) var scheme
    func body(content: Content) -> some View {
        content.overlay {
            Capsule()
                .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
        }
    }
}

/// Pillen-Knopf im Web-Stil (`static/uber.css`, volle Rundung).
public struct PillButton: View {
    public let title: String
    public let style: PillStyle
    public let action: () -> Void

    public init(_ title: String, style: PillStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
        }
        .buttonStyle(UberButtonStyle(style))
        .modifier(LightBorderIfNeeded(style: style))
        .hoverLift()
    }
}

private struct LightBorderIfNeeded: ViewModifier {
    @Environment(\.colorScheme) var scheme
    let style: PillStyle
    func body(content: Content) -> some View {
        if style == .light || style == .smallLight {
            content.overlay {
                Capsule().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
            }
        } else {
            content
        }
    }
}

// MARK: - Gemeinsame Schaltflächen-Schnittstelle (Paket 0/F, für alle Pakete)
//
// Verbindlich für alle macOS-Ansichten, damit nirgends die native
// Standardknopf-Optik (Bezel) erscheint:
//
// - Textknöpfe → `PillButton` oder `Button` + `.buttonStyle(UberButtonStyle(...))`.
// - Icon-knöpfe (nur Symbol, kein Text) → `IconButton` (nie `Button` + `Image`
//   mit Standard-Stil). Enthält Kreis-Hover, sichtbaren Fokus-Ring,
//   VoiceOver-Namen (`label`) und Tooltip (`help`, fällt auf `label` zurück).
// - Zeilen-/Karten-Taps → `Button` + `.buttonStyle(.plain)` (eigene Optik,
//   Label immer mit `.accessibilityLabel`, Icon-only zusätzlich mit `.help`).
//
// Tastatur (Tab + Return/Leer), VoiceOver-Namen, Tooltips und Fokuszustände
// bleiben dabei immer erhalten — die Stile ändern nur die Optik, nie das
// darunterliegende `Button`-Verhalten.

/// Einheitliche Icon-Schaltfläche (32pt, Kreis-Hover, Fokus-Ring in Akzent).
public struct IconButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @FocusState private var focused: Bool
    @State private var hovering = false
    public let icon: String
    public let label: String
    public let help: String?
    public let disabled: Bool
    public let action: () -> Void

    public init(
        icon: String,
        label: String,
        help: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.help = help
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EduFlowPalette.ink(scheme))
                .frame(width: 32, height: 32)
                .background(hovering ? EduFlowPalette.surface2(scheme) : Color.clear)
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(
                            focused ? accent.resolved(scheme) : Color.clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.plain)
        .focused($focused)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(LocalizedStringKey(label))
        .help(help ?? label)
        .onHover { hovering = $0 && !disabled }
    }
}

// MARK: - Karten (`.card`, 14px, 1px Rahmen)

///
/// Hintergrund Karte, 1px Rahmen, 14px Radius, Innenabstand 20/22.
public struct UberCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
    }
}

/// Hausaufgaben-Karte mit 6px Status-Kante (`.hw.st-*`), erledigt blass,
/// Papierkorb gestrichelt mit durchgestrichenem Titel.
public struct HomeworkCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let status: String
    private let isDone: Bool
    private let isHidden: Bool
    private let content: Content

    public init(status: String, isDone: Bool, isHidden: Bool, @ViewBuilder content: () -> Content) {
        self.status = status
        self.isDone = isDone
        self.isHidden = isHidden
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        EduFlowPalette.border(scheme),
                        style: StrokeStyle(lineWidth: 1, dash: isHidden ? [6, 4] : [])
                    )
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(EduFlowPalette.homeworkEdge(status, scheme: scheme))
                    .frame(width: 6)
                    .padding(.vertical, 1)
            }
            .opacity(isDone ? 0.65 : (isHidden ? 0.55 : 1))
    }
}

// MARK: - Tags (`.tag`, 11px/700 Pillen)

/// Tag-Stile wie im Web: solid/soft/outline/muted plus Statusfarben.
public enum TagStyle {
    case solid
    case soft
    case outline
    case muted
    case red
    case amber
    case blue
    case green
    case gray
}

public struct Tag: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    public let text: String
    public let style: TagStyle

    public init(_ text: String, style: TagStyle = .soft) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(LocalizedStringKey(text))
            .font(UberFont.text(11, weight: .bold))
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(.capsule)
            .overlay(borderOverlay)
    }

    private var backgroundColor: Color {
        switch style {
        case .solid: accent.resolved(scheme)
        case .soft: EduFlowPalette.surface2(scheme)
        case .outline: Color.clear
        case .muted: EduFlowPalette.surface1(scheme)
        case .red: EduFlowPalette.red
        case .amber: EduFlowPalette.amber
        case .blue: EduFlowPalette.blue
        case .green: EduFlowPalette.green
        case .gray: EduFlowPalette.surface2(scheme)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .solid: accent.resolvedInk(scheme)
        case .soft: EduFlowPalette.ink(scheme)
        case .outline: EduFlowPalette.ink(scheme)
        case .muted: EduFlowPalette.inkMuted(scheme)
        case .red, .amber, .blue, .green: Color.white
        case .gray: EduFlowPalette.inkMuted(scheme)
        }
    }

    private var borderOverlay: some View {
        Group {
            if style == .outline {
                Capsule().stroke(EduFlowPalette.ink(scheme), lineWidth: 1)
            } else if style == .muted {
                Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
        }
    }
}

// MARK: - Seitenkopf (`.page-head`: Eyebrow + H1 + Stats)

/// Versalien-Pille in Akzent (`.eyebrow`).
public struct Eyebrow: View {
    @Environment(\.uberAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(LocalizedStringKey(text))
            .textCase(.uppercase)
            .font(UberFont.text(12, weight: .bold))
            .tracking(1.4)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(accent.resolved(scheme))
            .foregroundStyle(accent.resolvedInk(scheme))
            .clipShape(.capsule)
    }
}

/// Seitenkopf: fette enge Headline plus graue Stats-Zeile.
public struct PageHead: View {
    @Environment(\.colorScheme) private var scheme
    public let title: String
    public let stats: String?
    public let eyebrow: String?

    public init(_ title: String, eyebrow: String? = nil, stats: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Eyebrow(eyebrow)
            }
            Text(LocalizedStringKey(title))
                .font(UberFont.text(34, weight: .heavy))
                .tracking(-1.5)
                .lineLimit(2)
            if let stats {
                Text(LocalizedStringKey(stats))
                    .font(UberFont.text(15, weight: .medium))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Statistik-Karten (`.stat-grid`)

/// Zahl groß/fett plus Versalien-Label darunter.
public struct StatCard: View {
    @Environment(\.colorScheme) private var scheme
    public let number: String
    public let label: String
    public let tone: StatTone

    public enum StatTone {
        case plain
        case danger
        case ok
    }

    public init(_ number: String, label: String, tone: StatTone = .plain) {
        self.number = number
        self.label = label
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: number)
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(numberColor)
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(UberFont.text(12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }

    private var numberColor: Color {
        switch tone {
        case .plain: EduFlowPalette.ink(scheme)
        case .danger: EduFlowPalette.red
        case .ok: EduFlowPalette.green
        }
    }
}

// MARK: - Eingaben (`.input-pill`) und Hinweise (`.notice`)

/// Eigene Textfeld-Box im Web-Stil: komplett selbst gezeichnete Pille
/// (Apples Textfeld läuft nur unsichtbar als Eingabe-Maschine darunter
/// via `.plain`). Mit Icon, eigenem Placeholder, Clear-Button,
/// Fokus-Rahmen in Akzent und Fehlerzustand.
public struct UberTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String?
    var isError: Bool = false
    var autofocus: Bool = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent

    public init(
        text: Binding<String>,
        placeholder: String = "",
        icon: String? = nil,
        isError: Bool = false,
        autofocus: Bool = false,
        onSubmit: @escaping () -> Void = {}
    ) {
        _text = text
        self.placeholder = placeholder
        self.icon = icon
        self.isError = isError
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EduFlowPalette.inkDim(scheme))
                    .frame(width: 18)
            }
            TextField(
                "",
                text: $text,
                prompt: Text(LocalizedStringKey(placeholder))
                    .font(UberFont.text(14, weight: .medium))
                    .foregroundStyle(EduFlowPalette.inkDim(scheme))
            )
            .textFieldStyle(.plain)
            .font(UberFont.text(14, weight: .semibold))
            .foregroundStyle(EduFlowPalette.ink(scheme))
            .focused($focused)
            .onSubmit(onSubmit)
            .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common_clear_input", value: "Eingabe löschen", comment: "Eingabefeld: löschen"))
                .help(NSLocalizedString("common_clear_input", value: "Eingabe löschen", comment: "Eingabefeld: löschen"))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: focused || isError ? 1.5 : 1)
        }
        .shadow(
            color: .black.opacity(focused ? (scheme == .dark ? 0.4 : 0.1) : 0),
            radius: focused ? 12 : 0,
            y: focused ? 3 : 0
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear {
            if autofocus {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private var borderColor: Color {
        if isError {
            EduFlowPalette.red
        } else if focused {
            accent.resolved(scheme)
        } else if hovering {
            EduFlowPalette.inkMuted(scheme)
        } else {
            EduFlowPalette.borderStrong(scheme)
        }
    }
}

/// Eigene Passwort-Box: wie `UberTextField`, zusätzlich mit Auge
/// zum Ein-/Ausblenden (schaltet zwischen SecureField und TextField um).
public struct UberSecureField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String?
    var isError: Bool = false
    var autofocus: Bool = false
    var allowReveal: Bool = true
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var revealed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent

    public init(
        text: Binding<String>,
        placeholder: String = "",
        icon: String? = nil,
        isError: Bool = false,
        autofocus: Bool = false,
        allowReveal: Bool = true,
        onSubmit: @escaping () -> Void = {}
    ) {
        _text = text
        self.placeholder = placeholder
        self.icon = icon
        self.isError = isError
        self.autofocus = autofocus
        self.allowReveal = allowReveal
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EduFlowPalette.inkDim(scheme))
                    .frame(width: 18)
            }
            Group {
                if revealed {
                    TextField("", text: $text, prompt: promptText)
                } else {
                    SecureField("", text: $text, prompt: promptText)
                }
            }
            .textFieldStyle(.plain)
            .font(UberFont.text(14, weight: .semibold))
            .foregroundStyle(EduFlowPalette.ink(scheme))
            .focused($focused)
            .onSubmit(onSubmit)
            .autocorrectionDisabled()
            if allowReveal {
                Button {
                    revealed.toggle()
                    DispatchQueue.main.async { focused = true }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? NSLocalizedString("common_password_hide", value: "Passwort verbergen", comment: "Passwort: verbergen") : NSLocalizedString("common_password_show", value: "Passwort anzeigen", comment: "Passwort: anzeigen"))
                .help(revealed ? NSLocalizedString("common_password_hide", value: "Passwort verbergen", comment: "Passwort: verbergen") : NSLocalizedString("common_password_show", value: "Passwort anzeigen", comment: "Passwort: anzeigen"))
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common_clear_input", value: "Eingabe löschen", comment: "Eingabefeld: löschen"))
                .help(NSLocalizedString("common_clear_input", value: "Eingabe löschen", comment: "Eingabefeld: löschen"))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: focused || isError ? 1.5 : 1)
        }
        .shadow(
            color: .black.opacity(focused ? (scheme == .dark ? 0.4 : 0.1) : 0),
            radius: focused ? 12 : 0,
            y: focused ? 3 : 0
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear {
            if autofocus {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private var promptText: Text {
        Text(LocalizedStringKey(placeholder))
            .font(UberFont.text(14, weight: .medium))
            .foregroundStyle(EduFlowPalette.inkDim(scheme))
    }

    private var borderColor: Color {
        if isError {
            EduFlowPalette.red
        } else if focused {
            accent.resolved(scheme)
        } else if hovering {
            EduFlowPalette.inkMuted(scheme)
        } else {
            EduFlowPalette.borderStrong(scheme)
        }
    }
}

/// Pillen-Eingabe mit starkem Rahmen und Akzent-Fokus.
public struct UberInput: ViewModifier {
    @Environment(\.colorScheme) var scheme
    @FocusState private var focused: Bool

    public func body(content: Content) -> some View {
        content
            .font(UberFont.text(14, weight: .semibold))
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule()
                    .stroke(focused ? EduFlowPalette.ink(scheme) : EduFlowPalette.borderStrong(scheme), lineWidth: 1)
            }
            .focused($focused)
    }
}

public extension View {
    func uberInput() -> some View {
        modifier(UberInput())
    }
}

/// Hinweis-Box (`.notice`).
public struct Notice: View {
    @Environment(\.colorScheme) private var scheme
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(verbatim: text)
            .font(UberFont.text(14, weight: .medium))
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EduFlowPalette.surface1(scheme))
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
            }
    }
}

// MARK: - Zustände

/// Ladezustand (Mitte, Spinner).
public struct LoadingView: View {
    public init() {}

    public var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Fehlerzustand (Mitte, Meldung plus Wiederholen).
public struct ErrorView: View {
    public let message: String
    public let onRetry: () -> Void

    public init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(verbatim: message)
                .font(UberFont.text(15))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            PillButton("Erneut versuchen", action: onRetry)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Leerzustand (Mitte, Meldung).
public struct EmptyView: View {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        VStack {
            Spacer()
            Text(LocalizedStringKey(message))
                .font(UberFont.text(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Animationen (`.btn:hover`, `.anim-in`, `.now-dot`)

///
/// Hover hebt den Knopf 1px an (`.btn:hover{transform:translateY(-1px)}`).
public struct HoverLift<Content: View>: View {
    @State private var hovering = false
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .offset(y: hovering ? -1 : 0)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

public extension View {
    func hoverLift() -> some View {
        HoverLift { self }
    }
}

/// Reinbouncen von unten (`.anim-in`, Kurve 1:1 aus `uber.css`),
/// gestaffelt per `delay` wie `--d`.
public struct RiseIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private let delay: Double

    public init(delay: Double = 0) {
        self.delay = delay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .scaleEffect(shown ? 1 : 0.985)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(
                        .timingCurve(0.22, 0.8, 0.32, 1.12, duration: 0.55).delay(delay)
                    ) {
                        shown = true
                    }
                }
            }
    }
}

public extension View {
    func riseIn(delay: Double = 0) -> some View {
        modifier(RiseIn(delay: delay))
    }
}

/// Pulsierender Punkt (`.now-dot`, 2s-Zyklus, White auf Schwarz).
public struct PulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private let color: Color

    public init(_ color: Color = .white) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(reduceMotion ? 1 : (pulse ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Animierter Gruß für den Einstieg: Die Buchstaben federn nacheinander
/// ein, danach winkt die Hand sanft weiter. Respektiert "Bewegung
/// reduzieren" (dann steht alles sofort still da).
public struct HelloGreeting: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCount = 0
    @State private var waving = false
    @State private var displayedText: String
    @State private var waveStarted = false

    private let text: String
    private let fontSize: CGFloat
    private let cycleGreetings: [String]?

    public init(_ text: String = "Hallo!", fontSize: CGFloat = 44, cycleGreetings: [String]? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.cycleGreetings = cycleGreetings
        _displayedText = State(initialValue: cycleGreetings?.first ?? text)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(displayedText.enumerated()), id: \.offset) { index, char in
                Text(verbatim: String(char))
                    .font(UberFont.text(fontSize, weight: .heavy))
                    .tracking(-1.5)
                    .foregroundStyle(EduFlowPalette.ink(scheme))
                    .opacity(index < visibleCount ? 1 : 0)
                    .offset(y: index < visibleCount ? 0 : 22)
                    .scaleEffect(index < visibleCount ? 1 : 0.85)
            }
            Image(systemName: "hand.wave.fill")
                .font(.system(size: fontSize * 0.8, weight: .semibold))
                .foregroundStyle(accent.resolved(scheme))
                .rotationEffect(.degrees(waving ? 18 : -12), anchor: .bottomLeading)
                .padding(.leading, 12)
                .opacity(visibleCount >= displayedText.count ? 1 : 0)
        }
        .task {
            if let greetings = cycleGreetings, !greetings.isEmpty {
                await runCycle(greetings)
            } else {
                await typeIn(displayedText)
                startWave()
            }
        }
    }

    /// Tippt den Text Buchstabe für Buchstabe ein (ohne Motion: sofort).
    private func typeIn(_ string: String) async {
        if reduceMotion {
            visibleCount = string.count
            return
        }
        visibleCount = 0
        for (i, _) in string.enumerated() {
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                visibleCount = i + 1
            }
        }
    }

    private func startWave() {
        guard !waveStarted else { return }
        waveStarted = true
        if reduceMotion { return }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            waving = true
        }
    }

    /// Wechselt die Begrüßung alle zwei Sekunden in zufälliger Reihenfolge
    /// (Onboarding-Hallo, ohne direkten Wiederholer am Rundenübergang).
    private func runCycle(_ greetings: [String]) async {
        guard !greetings.isEmpty else { return }
        var lastIndex: Int?
        while !Task.isCancelled {
            for index in AppLocalizations.shuffledCycle(count: greetings.count, notStartingWith: lastIndex) {
                displayedText = greetings[index]
                await typeIn(displayedText)
                guard !Task.isCancelled else { return }
                startWave()
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    visibleCount = 0
                } else {
                    withAnimation(.easeOut(duration: 0.25)) {
                        visibleCount = 0
                    }
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled else { return }
                }
                lastIndex = index
            }
        }
    }
}

/// Kleine Marken-Box (`.brand-mark`): Logo aus `Resources/icon.png`,
/// fällt auf die E-Kachel zurück, falls das Bild fehlt.
public struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    private let size: CGFloat

    public init(size: CGFloat = 32) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let nsImage = NSImage(named: "icon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.31))
            } else {
                Text(verbatim: "E")
                    .font(UberFont.text(size * 0.58, weight: .black))
                    .foregroundStyle(accent.resolvedInk(scheme))
                    .frame(width: size, height: size)
                    .background(accent.resolved(scheme))
                    .clipShape(.rect(cornerRadius: size * 0.31))
            }
        }
    }
}

/// App-Logo aus `static/icons/icon.png` (liegt im Bundle unter
/// Resources) freistehend ohne Rahmen. Fällt auf die E-Kachel zurück,
/// falls das Bild fehlt.
public struct AppLogo: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent

    public init() {}

    public var body: some View {
        Group {
            if let nsImage = NSImage(named: "icon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 22))
                    .shadow(
                        color: .black.opacity(0.25),
                        radius: 16,
                        y: 4
                    )
            } else {
                Text(verbatim: "E")
                    .font(UberFont.text(34, weight: .black))
                    .foregroundStyle(accent.resolvedInk(scheme))
                    .frame(width: 92, height: 92)
                    .background(accent.resolved(scheme))
                    .clipShape(.rect(cornerRadius: 22))
            }
        }
    }
}
