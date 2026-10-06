import AppKit
import SwiftUI

// MARK: - Sprachwahl (Profilmenü, eigene Pillen — keine System-Schalter)

/// Eine Sprache mit ihrem Übersetzungsstand, aus dem Bundle gelesen
/// (`AppLocalizations.coverage()`). Neue Crowdin-Sprachen erscheinen damit
/// automatisch, ohne dass hier Code nachgezogen werden muss.
public struct LanguageEntry: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String
    public let percent: Int
    public let translated: Int
    public let total: Int

    public var id: String { code }

    /// Katalog-Sprachen mit Eigenname und Stand, nach Eigenname sortiert.
    /// Die System-Sprache steht nicht in der Liste (sie hat keinen Code in
    /// der Auswahl) und wird separat angeboten.
    public static func fromBundle(in bundle: Bundle = .main) -> [LanguageEntry] {
        AppLocalizations.coverage(in: bundle)
            .map {
                LanguageEntry(
                    code: $0.code,
                    name: AppLanguage.nativeName($0.code),
                    percent: $0.percent,
                    translated: $0.translated,
                    total: $0.total
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

/// Sprachauswahl als eigene Oberfläche: Suchleiste, Pillen-Liste mit
/// Prozentzahl und Fortschrittsbalken. Bewusst ohne `Picker`, `Menu` oder
/// `Toggle` — die Gestaltung folgt den App-Pillen (`.btn`), damit nichts
/// als System-Steuerelement durchschimmert.
///
/// Wirkt sofort (Bundle-Überlagerung, kein Neustart) und informiert über
/// `.appLanguageDidChange`, damit alle Ansichten neu rendern.
public struct LanguageSwitcher: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @State private var entries = LanguageEntry.fromBundle()
    @State private var query = ""
    /// `nil` = Systemsprache. Startwert aus dem Store, nicht aus der
    /// Umgebung (damit der Ausgangszustand auch stimmt, wenn die App
    /// gerade neu gestartet wurde).
    @State private var selection: String?
    /// Beim Öffnen einer neuen Liste neu aus dem Bundle lesen.
    @State private var refreshToken = 0

    public init() {
        _selection = State(initialValue: AppLanguage.override)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            UberTextField(
                text: $query,
                placeholder: NSLocalizedString("language_search_placeholder", value: "Search language", comment: "Sprachwahl: Platzhalter"),
                icon: "magnifyingglass"
            )
            list
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            // Auswahl und Stand frisch halten, wenn die Sprache von woanders
            // (Onboarding) gewechselt wurde.
            selection = AppLanguage.override
            reload()
        }
        .onChange(of: refreshToken) { _, _ in reload() }
    }

    /// Kompakter Kopf: Titel und erklärender Text. Die aktive Sprache steht
    /// nicht extra daneben — sie ist unten in ihrer eigenen Zeile markiert.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.resolvedInk(scheme))
                Text(NSLocalizedString("language_title", value: "Language", comment: "Sprachwahl: Titel"))
                    .font(UberFont.text(15, weight: .heavy))
                    .tracking(-0.2)
            }
            Text(NSLocalizedString("language_hint", value: "Takes effect right away. The percentage shows how much is translated.", comment: "Sprachwahl: Hinweis"))
                .font(UberFont.text(12))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .lineSpacing(2)
        }
    }

    /// Systemsprache plus gefilterte Sprachen, jede Zeile eine Pille.
    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                systemRow
                ForEach(filtered) { entry in
                    languageRow(entry)
                }
                if !filtered.isEmpty {
                    emptyHint
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 260)
    }

    private var filtered: [LanguageEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.lowercased().contains(needle) || entry.code.lowercased().hasPrefix(needle)
        }
    }

    private var emptyHint: some View {
        Text(NSLocalizedString("language_no_match", value: "No language matches that.", comment: "Sprachwahl: kein Treffer"))
            .font(UberFont.text(12))
            .foregroundStyle(EduFlowPalette.inkDim(scheme))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
    }

    /// Systemsprache ohne Prozent: sie folgt dem System, ihre Texte sind
    /// automatisch da.
    private var systemRow: some View {
        Button {
            choose(nil)
        } label: {
            rowLabel(
                name: NSLocalizedString("language_system", value: "System language", comment: "Sprachwahl: Systemsprache"),
                detail: NSLocalizedString("language_system_detail", value: "Follows macOS", comment: "Sprachwahl: Systemsprache Detail"),
                percent: nil,
                selected: selection == nil,
                query: nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("language_system", value: "System language", comment: "Sprachwahl: Systemsprache"))
    }

    private func languageRow(_ entry: LanguageEntry) -> some View {
        Button {
            choose(entry.code)
        } label: {
            rowLabel(
                name: entry.name,
                detail: String(
                    format: NSLocalizedString("language_progress", value: "%d of %d texts", comment: "Sprachwahl: Fortschritt"),
                    entry.translated,
                    entry.total
                ),
                percent: entry.percent,
                selected: selection == entry.code,
                query: query.isEmpty ? nil : query
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .accessibilityValue("\(entry.percent) %")
    }

    /// Zeileninhalt. `query` hebt den passenden Teil im Namen hervor, damit
    /// die Suche sichtbar wirkt (eigene Pille, kein System-Textfeld).
    private func rowLabel(
        name: String,
        detail: String,
        percent: Int?,
        selected: Bool,
        query: String?
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(selected ? accent.resolved(scheme) : EduFlowPalette.borderStrong(scheme), lineWidth: 2)
                    .frame(width: 18, height: 18)
                if selected {
                    Circle()
                        .fill(accent.resolved(scheme))
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                highlighted(name, needle: query)
                    .font(UberFont.text(13, weight: .heavy))
                    .tracking(-0.2)
                if let percent {
                    // Fortschrittsbalken wie in der Onboarding-Sprachseite.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(EduFlowPalette.surface2(scheme))
                            Capsule()
                                .fill(percent >= 90 ? EduFlowPalette.green : accent.resolved(scheme))
                                .frame(width: geometry.size.width * CGFloat(percent) / 100)
                        }
                    }
                    .frame(height: 4)
                }
                Text(detail)
                    .font(UberFont.text(11))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
            Spacer(minLength: 6)
            if let percent {
                Text("\(percent) %")
                    .font(UberFont.text(13, weight: .heavy))
                    .foregroundStyle(percent >= 90 ? EduFlowPalette.green : EduFlowPalette.ink(scheme))
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? accent.resolved(scheme).opacity(0.10) : EduFlowPalette.surface1(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule().stroke(selected ? accent.resolved(scheme) : EduFlowPalette.border(scheme), lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    /// Name mit hervorgehobenem Suchtreffer.
    private func highlighted(_ name: String, needle: String?) -> Text {
        guard let needle, !needle.isEmpty,
              let range = name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return Text(verbatim: name)
        }
        let prefix = String(name[range.lowerBound..<range.upperBound])
        let suffix = String(name[range.upperBound...])
        return Text(verbatim: String(name[..<range.lowerBound]))
            + Text(verbatim: prefix).bold().foregroundStyle(accent.resolved(scheme))
            + Text(verbatim: suffix)
    }

    /// Auswahl anwenden: sofort, ohne Neustart, und den Stand neu lesen.
    private func choose(_ code: String?) {
        selection = code
        AppLanguage.set(code)
        reload()
    }

    private func reload() {
        entries = LanguageEntry.fromBundle()
    }
}

// MARK: - Suchfeld (`.searchbar`)

/// Suchfeld im Web-Stil (`.searchbar`): **selbst gezeichnet**, kein
/// `NSSearchField` und keine System-Steuerelement-Kante.
///
/// Vorher lag hier eine AppKit-Brücke auf `NSSearchField`. Sie lieferte
/// Fokus, Lupe und Kreuz-Knopf mit Systemoptik — genau die Elemente, die in
/// dieser App nirgends sonst auftauchen (alle anderen Felder sind eigene
/// Pillen aus `UberTextField`). Alles, was die Suchleiste tatsächlich
/// braucht, ist hier von Hand gebaut:
///
/// - Fokus-Ring in Akzentfarbe (wie `UberTextField`)
/// - Lupe als eigenes Symbol, Kreuz-Knopf als eigener `IconButton`
/// - Platzhalter in derselben Schrift wie der Inhalt
/// - Esc leert das Feld, Return löst `onSubmit` aus
///
/// Der Fokus hängt an `@FocusState`, damit `autofocus` und der Ring ohne
/// Fensterzugriff funktionieren.
public struct UberSearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}
    /// Fokus sofort setzen (wichtig, wenn die Ansicht frisch eingeblendet wird).
    var autofocus: Bool = false

    @FocusState private var focused: Bool
    @State private var hovering = false

    public init(
        text: Binding<String>,
        prompt: String = "",
        onSubmit: @escaping () -> Void = {},
        autofocus: Bool = false
    ) {
        _text = text
        self.prompt = prompt
        self.onSubmit = onSubmit
        self.autofocus = autofocus
    }

    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkDim(scheme))
            TextField(
                "",
                text: $text,
                prompt: Text(LocalizedStringKey(prompt))
                    .font(UberFont.text(13, weight: .medium))
                    .foregroundStyle(EduFlowPalette.inkDim(scheme))
            )
            .textFieldStyle(.plain)
            .font(UberFont.text(13, weight: .semibold))
            .foregroundStyle(EduFlowPalette.ink(scheme))
            .focused($focused)
            .onSubmit(onSubmit)
            .autocorrectionDisabled()
            // Esc leert das Feld (wie die frühere System-Suchleiste).
            .onExitCommand { text = "" }
            if !text.isEmpty {
                IconButton(
                    icon: "xmark",
                    label: NSLocalizedString(
                        "common_clear_input", value: "Clear input",
                        comment: "Eingabefeld: löschen"
                    )
                ) {
                    text = ""
                    focused = true
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(EduFlowPalette.surface2(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: focused ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
        .onHover { hovering = $0 }
        .onAppear {
            if autofocus {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private var borderColor: Color {
        if focused { return accent.resolved(scheme) }
        if hovering { return EduFlowPalette.inkMuted(scheme) }
        return EduFlowPalette.border(scheme)
    }
}

// MARK: - Topbar reagiert auf Scrollen

/// Zustand der oberen Leiste beim Scrollen (reine Logik, testbar).
///
/// Beim Scrollen **nach unten** wird die Leiste kleiner (der Inhalt rückt
/// nach oben, die Leiste soll aus dem Weg); beim Scrollen **nach oben** und
/// ganz oben am Seitenanfang wächst sie wieder. Am Offset 0 ist sie immer
/// groß, sonst wäre sie beim Seitenwechsel verschwunden.
@MainActor
@Observable
public final class TopBarCollapseState {
    /// Oberhalb dieses Offsets gilt „oben" → Leiste immer groß.
    public static let topThreshold: CGFloat = 12
    /// Mindestbewegung, ab der die Richtung überhaupt zählt (sonst zappelt
    /// sie bei Trackpad-Gesten mit 1 Pixel).
    public static let minimumDelta: CGFloat = 2

    public private(set) var isCompact = false
    private var lastOffset: CGFloat = 0

    public init() {}

    /// Scrollposition melden; rechnet die neue Größe aus (rein, testbar).
    @discardableResult
    public func update(offset: CGFloat) -> Bool {
        let clamped = max(offset, 0)
        let delta = clamped - lastOffset
        if clamped <= Self.topThreshold {
            isCompact = false
        } else if abs(delta) >= Self.minimumDelta {
            // Nach unten scrollen (Offset wächst) → klein; nach oben → groß.
            isCompact = delta > 0
        }
        lastOffset = clamped
        return isCompact
    }

    /// Zustand vergessen (Seitenwechsel): die neue Seite beginnt oben, also
    /// muss die Leiste wieder groß sein und der Vergleich neu ansetzen.
    public func reset() {
        lastOffset = 0
        isCompact = false
    }
}

/// Meldet das Scrollen einer Seite an die obere Leiste.
///
/// Zwei Wege, weil das Projekt macOS 14 als Ziel hat:
/// - ab macOS 15 `onScrollGeometryChange` (die SwiftUI-eigene Größe),
/// - darunter die Fenster-Suche in `TopBarScrollObserver`.
///
/// Als **erstes Kind** in die `ScrollView` gelegt; unsichtbar.
public struct ScrollOffsetSentinel: View {
    @Environment(\.topBarCollapse) private var collapse

    public init() {}

    public var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Color.clear
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        // Nach oben gescrollt ist der Versatz negativ.
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        collapse.update(offset: offset)
                    }
            } else {
                // Ältere Systeme übernimmt der fensterweite Beobachter.
                Color.clear
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Zustand in der Umgebung — bewusst als eigener Schlüssel und **nicht** als
/// `@Environment(TopBarCollapseState.self)`: fehlte er, würde SwiftUI beim
/// Rendern abstürzen. Mit Vorgabe bleibt die Seite beim Vorentwurf oder in
/// einer Testansicht schlicht ohne Reaktion.
private struct TopBarCollapseKey: EnvironmentKey {
    /// Gemeinsame Vorgabe: wird nur benutzt, wenn niemand einen Zustand
    /// gesetzt hat (Vorschau, isolierte Testansicht).
    @MainActor static let defaultValue = TopBarCollapseState()
}

extension EnvironmentValues {
    /// Zustand der oberen Leiste (siehe `TopBarCollapseState`).
    public var topBarCollapse: TopBarCollapseState {
        get { self[TopBarCollapseKey.self] }
        set { self[TopBarCollapseKey.self] = newValue }
    }
}

/// Rückfallebene für macOS 14 (dort gibt es `onScrollGeometryChange` noch
/// nicht): sucht die scrollbare Ansicht der geöffneten Seite im Fenster und
/// beobachtet deren Clip-View. Ab macOS 15 macht `ScrollOffsetSentinel` das
/// schon selbst, deshalb läuft dieser Weg nur auf älteren Systemen.
public struct TopBarScrollObserver: View {
    let state: TopBarCollapseState
    /// Zähler für „Seite gewechselt" — treibt die Suche neu.
    let token: Int

    public init(state: TopBarCollapseState, token: Int) {
        self.state = state
        self.token = token
    }

    public var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Color.clear
            } else {
                ScrollOffsetReporter(state: state, token: token)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Trägeransicht: sobald sie im Fenster hängt, wird der passende
/// Scrollbereich gesucht und beobachtet.
private final class ScrollObserverView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Eine Runde warten: erst dann ist der Seiteninhalt im Baum.
        DispatchQueue.main.async { [weak self] in
            self?.onWindowChange?()
        }
    }
}

private struct ScrollOffsetReporter: NSViewRepresentable {
    let state: TopBarCollapseState
    let token: Int

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    @MainActor
    func makeNSView(context: Context) -> ScrollObserverView {
        let view = ScrollObserverView(frame: .zero)
        view.onWindowChange = { context.coordinator.scan(from: view) }
        context.coordinator.scan(from: view)
        return view
    }

    @MainActor
    func updateNSView(_ nsView: ScrollObserverView, context: Context) {
        context.coordinator.state = state
        // Jede Aktualisierung prüft neu: beim Seitenwechsel entsteht eine
        // andere Scrollansicht, die alte Beobachtung muss weg.
        context.coordinator.scan(from: nsView, force: context.coordinator.token != token)
        context.coordinator.token = token
    }

    @MainActor
    final class Coordinator: NSObject {
        var state: TopBarCollapseState
        var token: Int = 0
        private weak var watched: NSScrollView?
        private var observation: NSKeyValueObservation?
        private var attempts = 0

        init(state: TopBarCollapseState) {
            self.state = state
        }

        deinit {
            observation?.invalidate()
        }

        /// Die scrollbare Ansicht der geöffneten Seite suchen und beobachten.
        func scan(from view: NSView, force: Bool = false) {
            guard let window = view.window else {
                retry(from: view)
                return
            }
            if force {
                observation?.invalidate()
                observation = nil
                watched = nil
                attempts = 0
            }
            guard observation == nil else { return }

            guard let scroll = Self.scrollableScrollView(in: window) else {
                // Inhalt ist noch nicht da: ein paarmal nachfassen.
                retry(from: view)
                return
            }
            let clip = scroll.contentView
            watched = scroll
            attempts = 0
            state.reset()
            observation = clip.observe(\.bounds, options: [.new]) { [weak self] _, change in
                guard let self, let bounds = change.newValue else { return }
                // Nach unten scrollen bewegt das Clip-View nach oben, sein
                // Ursprung bekommt also einen negativen Y-Wert.
                let scrollable = scroll.contentSize.height - clip.bounds.height
                let offset = scrollable > 0 ? -bounds.origin.y : 0
                Task { @MainActor in
                    self.state.update(offset: offset)
                }
            }
        }

        /// Kurzzeitig weiter versuchen (Inhalt baut sich asynchron auf).
        private func retry(from view: NSView) {
            guard attempts < 12 else { return }
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak view] in
                guard let self, let view else { return }
                self.scan(from: view)
            }
        }

        /// Erste waagerecht unscrollbare, aber senkrecht scrollbare Ansicht
        /// im Fenster — das ist die Liste der geöffneten Seite.
        private static func scrollableScrollView(in window: NSWindow) -> NSScrollView? {
            guard let content = window.contentView else { return nil }
            var found: NSScrollView?
            func walk(_ view: NSView) {
                if found != nil { return }
                if let scroll = view as? NSScrollView {
                    let vertical = scroll.hasVerticalScroller
                        && scroll.contentSize.height > scroll.contentView.bounds.height + 1
                    let horizontal = scroll.hasHorizontalScroller
                        && scroll.contentSize.width > scroll.contentView.bounds.width + 1
                    if vertical && !horizontal {
                        found = scroll
                        return
                    }
                }
                for sub in view.subviews { walk(sub) }
            }
            walk(content)
            return found
        }
    }
}

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

/// Auswahlzeile mit eigenem Kreis-Knopf (statt `Toggle`).
///
/// Eigener Knopf statt System-Kästchen: `Toggle` brachte die NS-Optik mit.
/// Der Knopf ist ein `Button` mit `.isSelected`-Trait, damit VoiceOver den
/// Zustand weiterhin als „an/aus" vorliest.
public struct UberCheckRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    public let isOn: Bool
    public let action: () -> Void
    private let content: AnyView

    public init<Content: View>(
        isOn: Bool,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) {
        self.isOn = isOn
        self.action = action
        self.content = AnyView(content())
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        isOn ? accent.resolved(scheme) : EduFlowPalette.inkMuted(scheme)
                    )
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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
        .help(LocalizedStringKey(help ?? label))
        .onHover { hovering = $0 && !disabled }
    }
}

// MARK: - Schalter, Zähler, Segmentwahl (statt `Toggle`/`Stepper`/`Picker`)
//
// Die drei System-Steuerelemente wurden durch eigene Pillen ersetzt. Grund:
// `Toggle` (NS-Switch), `Stepper` (NS-Stepper) und `Picker` (NS-PopUpButton)
// brachten die Systemoptik und -Maße mit, die es sonst nirgends in der App
// gibt. Verhalten bleibt erhalten: Tastaturbedienung, VoiceOver-Rolle und
// Tooltips sind unten ausdrücklich gesetzt, damit die Eigenoptik nichts
// kostet.

/// Schalter-Pille im Web-Stil: Beschriftung links, Wippe rechts.
///
/// Ersetzt `Toggle`. Die Wippe ist eine eigene Zeichnung; der Button trägt
/// `accessibilityAddTraits(.isSelected)`, damit VoiceOver „an/aus" meldet.
public struct UberToggle: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Binding private var isOn: Bool
    public let label: String
    public let help: String?

    public init(
        _ label: String,
        isOn: Binding<Bool>,
        help: String? = nil
    ) {
        self.label = label
        self.help = help
        _isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Text(LocalizedStringKey(label))
                    .font(UberFont.text(14, weight: .medium))
                    .foregroundStyle(EduFlowPalette.ink(scheme))
                Spacer(minLength: 0)
                knob
                    .frame(width: 44, height: 24)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.capsule)
            .overlay {
                // Der Rahmen bleibt in beiden Zuständen gleich — sonst wirkt
                // die Zeile beim Umschalten springend.
                Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(label))
        .accessibilityValue(
            isOn
                ? NSLocalizedString("common_on", value: "On", comment: "Schalter: an")
                : NSLocalizedString("common_off", value: "Off", comment: "Schalter: aus")
        )
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .help(LocalizedStringKey(help ?? label))
    }

    /// Wippe: Kreis wandert auf der Fläche, Fläche folgt dem Schalterzustand.
    ///
    /// Fläche und Kreis liegen in **einem** `ZStack` mit fester Größe
    /// 44×24. Das ist der entscheidende Punkt: läge der Kreis in einem
    /// zweiten `.overlay`, bekäme er die volle Overlay-Fläche und würde
    /// sich zur Ellipse dehnen; läge er in einem `ZStack` neben einem
    /// `Spacer`, dehnte der Spacer die Klammer über die Fläche hinaus.
    /// Der Rand von 3 pt steckt im Padding des Kreises.
    private var knob: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? accent.resolved(scheme) : EduFlowPalette.surface2(scheme))
                .overlay {
                    Capsule().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                }
            Circle()
                // `resolvedInk` ist die Schriftfarbe **auf** der Akzentfläche
                // (bei Schwarz im Dark-Modus wird der Kreis also dunkel).
                // Fester Weiß wäre unsichtbar, weil der Standardakzent
                // `black` im Dark-Modus selbst zu Weiß auflöst.
                .fill(accent.resolvedInk(scheme))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(
                        EduFlowPalette.borderStrong(scheme).opacity(0.6),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(.horizontal, 3)
        }
        .frame(width: 44, height: 24)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

/// Zähler-Pille im Web-Stil: minus, Wert, plus.
///
/// Ersetzt `Stepper`. Der Kern ist ein einzeiliges `TextField`, damit der
/// Wert wie in der Web-Oberfläche direkt tippbar bleibt (der System-Stepper
/// erlaubte nur Tippen auf die Pfeile).
public struct UberStepper: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Binding private var value: Int
    public let range: ClosedRange<Int>
    public let label: String

    @FocusState private var focused: Bool

    public init(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int> = 1...50
    ) {
        self.label = label
        self.range = range
        _value = value
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(UberFont.text(14, weight: .medium))
                .foregroundStyle(EduFlowPalette.ink(scheme))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                step(
                    icon: "minus",
                    delta: -1,
                    enabled: value > range.lowerBound,
                    label: NSLocalizedString(
                        "common_decrease", value: "Decrease",
                        comment: "Zähler: verringern"
                    )
                )
                TextField("", text: Binding(
                    get: { String(value) },
                    set: { raw in
                        let digits = raw.filter(\.isNumber)
                        // Mehr als zwei Stellen sind in diesem Bereich
                        // sinnlos; Eingabe auf Zeichen beschränken.
                        guard let parsed = Int(digits.prefix(2)) else { return }
                        value = min(max(parsed, range.lowerBound), range.upperBound)
                    }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(UberFont.text(14, weight: .bold))
                .foregroundStyle(EduFlowPalette.ink(scheme))
                .frame(width: 42)
                .focused($focused)
                step(
                    icon: "plus",
                    delta: 1,
                    enabled: value < range.upperBound,
                    label: NSLocalizedString(
                        "common_increase", value: "Increase",
                        comment: "Zähler: erhöhen"
                    )
                )
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
            .background(EduFlowPalette.surface2(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }

    private func step(icon: String, delta: Int, enabled: Bool, label: String) -> some View {
        Button {
            guard enabled else { return }
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    enabled ? EduFlowPalette.ink(scheme) : EduFlowPalette.inkDim(scheme)
                )
                .frame(width: 26, height: 26)
                .contentShape(.rect)
                .background(EduFlowPalette.card(scheme).opacity(0.6))
                .clipShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(LocalizedStringKey(label))
    }
}

/// Segmentwahl im Web-Stil: eine Pillen-Reihe mit genau einer Auswahl.
///
/// Ersetzt `Picker`. Anders als `NSPopUpButton` ist die Auswahl sofort
/// sichtbar (kein Aufklappen), und die Pillenreihe entspricht der
/// Filterleiste der Web-Oberfläche.
public struct UberSegmented<Value: Hashable>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Binding private var selection: Value
    public let options: [Value]
    public let label: (Value) -> String

    public init(
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) {
        self.options = options
        self.label = label
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    selection = option
                } label: {
                    Text(LocalizedStringKey(label(option)))
                        .font(UberFont.text(13, weight: .semibold))
                        .fixedSize()
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            active ? EduFlowPalette.surface2(scheme) : Color.clear
                        )
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey(label(option)))
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.capsule)
        .overlay {
            Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: selection)
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
                .accessibilityLabel(NSLocalizedString("common_clear_input", value: "Clear input", comment: "Eingabefeld: löschen"))
                .help(NSLocalizedString("common_clear_input", value: "Clear input", comment: "Eingabefeld: löschen"))
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
                .accessibilityLabel(revealed ? NSLocalizedString("common_password_hide", value: "Hide password", comment: "Passwort: verbergen") : NSLocalizedString("common_password_show", value: "Show password", comment: "Passwort: anzeigen"))
                .help(revealed ? NSLocalizedString("common_password_hide", value: "Hide password", comment: "Passwort: verbergen") : NSLocalizedString("common_password_show", value: "Show password", comment: "Passwort: anzeigen"))
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common_clear_input", value: "Clear input", comment: "Eingabefeld: löschen"))
                .help(NSLocalizedString("common_clear_input", value: "Clear input", comment: "Eingabefeld: löschen"))
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

/// Offline-Hinweis (`.notice`, gedämpfte Variante).
///
/// Sichtbar, wenn eine Liste aus dem lokalen Cache kommt — meist weil
/// das Backend neu gestartet wurde und der Bearer-Token nicht mehr
/// gilt. Der Text nennt den Zeitpunkt, damit klar ist, dass die Daten
/// **nicht** frisch sind; ein Grund, sich neu anzumelden, ist das nicht.
public struct OfflineNotice: View {
    @Environment(\.colorScheme) private var scheme
    public let savedAt: Date?

    public init(savedAt: Date?) {
        self.savedAt = savedAt
    }

    public var body: some View {
        if let savedAt {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text(
                    String(
                        format: NSLocalizedString(
                            "common_offline_cache",
                            value: "Showing saved data from %@ — the server is not reachable.",
                            comment: "Offline-Hinweis: Zeitpunkt der lokalen Daten"
                        ),
                        Self.relative(savedAt)
                    )
                )
                .font(UberFont.text(12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EduFlowPalette.surface2(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// „gerade eben" / „vor 5 Min." / mit Datum, wenn älter als ein Tag.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if seconds < 90 { return NSLocalizedString("common_just_now", value: "just now", comment: "Relative Zeit: gerade eben") }
        if seconds < 3600 { return formatter.localizedString(for: date, relativeTo: now) }
        if seconds < 86_400 {
            return String(
                format: NSLocalizedString("common_at_time", value: "today at %@", comment: "Relative Zeit: heute um"),
                date.formatted(date: .omitted, time: .shortened)
            )
        }
        return date.formatted(date: .abbreviated, time: .omitted)
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
            PillButton(NSLocalizedString("Try again", value: "Try again", comment: "Fehler: erneut versuchen"), action: onRetry)
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
