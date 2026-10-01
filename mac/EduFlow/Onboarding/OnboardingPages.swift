import AppKit
import Combine
import SwiftUI

/// Prüfergebnis des Server-Schritts (reine Werte, testbar vergleichbar).
public enum ServerCheckResult: Equatable, Sendable {
    case none
    case ok(version: String)
    case failed(message: String)
}

/// Server-Schritt-Logik: URL prüfen ohne zu speichern, erst
/// „Übernehmen & weiter" schreibt in den Store (wie Login-Ansicht).
@MainActor
@Observable
public final class ServerCheckModel {
    public var url: String
    public var checking = false
    public var result: ServerCheckResult = .none
    public var showSuccess = false
    /// Blendet die Erfolgs-Animation nach manuellem Test wieder aus.
    private var hideSuccessTask: Task<Void, Never>?

    private let store: TokenStore
    private let session: URLSession?

    public init(store: TokenStore, session: URLSession? = nil) {
        self.store = store
        self.session = session
        url = store.baseURLString
    }

    public func check() async {
        checking = true
        result = .none
        defer { checking = false }
        let target = OnboardingState.sanitizedBaseURL(url)
        let client = APIClient(
            baseURL: { target },
            token: { nil },
            session: session ?? TokenStore.defaultSession()
        )
        do {
            let health = try await client.health()
            result = .ok(version: health.version)
        } catch let apiError as APIError {
            result = .failed(message: apiError.message)
        } catch {
            result = .failed(message: APIError.englishFallback(for: ErrorCodes.upstream))
        }
    }

    public func apply() {
        store.setBaseURL(OnboardingState.sanitizedBaseURL(url))
        url = store.baseURLString
    }

    /// Status zurücksetzen (z. B. wenn die URL nach einem Test geändert
    /// wird, damit kein veraltetes Ergebnis angezeigt wird).
    public func resetResult() {
        result = .none
        cancelCelebration()
    }

    /// Erfolg feiern: großes Overlay-Häkchen einblenden und nach kurzer
    /// Zeit von selbst ausblenden (manueller Test; `proceed()` navigiert
    /// stattdessen weiter und braucht kein Ausblenden).
    public func celebrate() {
        hideSuccessTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            showSuccess = true
        }
        hideSuccessTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showSuccess = false
        }
    }

    /// Feier abbrechen (neuer Test, Zurücksetzen, Übernehmen).
    public func cancelCelebration() {
        hideSuccessTask?.cancel()
        hideSuccessTask = nil
        showSuccess = false
    }

    /// Weiter-Ablauf: testet direkt, zeigt bei Erfolg kurz das grüne
    /// Häkchen und übernimmt. Returns true, wenn fortgefahren werden
    /// darf — bei Fehler bleibt die Seite mit Meldung stehen.
    @discardableResult
    public func proceed(reduceMotion: Bool) async -> Bool {
        cancelCelebration()
        await check()
        guard case .ok = result else { return false }
        if !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                showSuccess = true
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return false }
        }
        apply()
        return true
    }
}

/// App-Logo (geteilt, siehe `AppLogo` in CommonViews).
/// Funkelnde Partikel hinter dem Logo wie bei boring.notch
/// (`SparkleView` mit `CAEmitterLayer`). Der Punkt wird per Code
/// erzeugt und grau getönt, damit er in Light und Dark sichtbar ist.
private final class SparkleNSView: NSView {
    private var emitterLayer: CAEmitterLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupEmitterLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func dotImage() -> CGImage? {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func setupEmitterLayer() {
        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterShape = .rectangle
        emitterLayer.emitterMode = .surface
        emitterLayer.renderMode = .oldestFirst

        let cell = CAEmitterCell()
        cell.contents = Self.dotImage()
        cell.color = NSColor.systemGray.cgColor
        cell.birthRate = 12
        cell.lifetime = 4
        cell.velocity = 8
        cell.velocityRange = 5
        cell.emissionRange = .pi * 2
        cell.scale = 0.2
        cell.scaleRange = 0.12
        cell.alphaSpeed = -0.25
        cell.yAcceleration = 6
        emitterLayer.emitterCells = [cell]

        layer?.addSublayer(emitterLayer)
        self.emitterLayer = emitterLayer
        updateEmitterForCurrentBounds()
    }

    private func updateEmitterForCurrentBounds() {
        guard let emitterLayer else { return }
        emitterLayer.frame = bounds
        emitterLayer.emitterSize = bounds.size
        emitterLayer.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateEmitterForCurrentBounds()
    }
}

private struct SparkleView: NSViewRepresentable {
    func makeNSView(context: Context) -> SparkleNSView {
        SparkleNSView()
    }

    func updateNSView(_ nsView: SparkleNSView, context: Context) {}
}

/// Partikel über die ganze App während des Onboardings: füllt das
/// Fenster und liegt hinter dem Inhalt (dezent wie die Logo-Funken).
/// Wird ausschließlich im `OnboardingFlow` eingebettet, respektiert
/// Reduce Motion und fängt keine Klicks ab.
struct OnboardingParticleBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            SparkleView()
                .opacity(0.35)
                .blur(radius: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Seite 2: Sprachauswahl mit Übersetzungsstand. Antippen wendet die Sprache
/// sofort an (laufender Prozess, kein Neustart); Weiter geht zur nächsten Seite.
public struct OnboardingLanguagePage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @State private var selected: String?
    @State private var rows = AppLocalizations.coverage()
    public let onNext: () -> Void

    public init(onNext: @escaping () -> Void) {
        _selected = State(initialValue: AppLanguage.override)
        self.onNext = onNext
    }

    /// Zeilen-Codes stabil nach Eigenname sortiert (kein Umsortieren bei
    /// Auswahl, sonst springt die getappte Zeile weg und wirkt falsch).
    private var orderedCodes: [String] {
        let codes = rows.map(\.code)
        return codes.sorted {
            AppLanguage.nativeName($0).localizedCaseInsensitiveCompare(AppLanguage.nativeName($1)) == .orderedAscending
        }
    }

    private func percent(of code: String) -> Int? {
        rows.first { $0.code == code }?.percent
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Choose language")
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-1.2)
                .padding(.top, 12)
                .riseIn(delay: 0.08)
            Text(NSLocalizedString("onboarding_language_subtitle", value: "EduFlow speaks your language. The choice applies immediately.", comment: "Onboarding: Sprachauswahl Untertitel"))
                .font(UberFont.text(14))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.horizontal, 24)
                .riseIn(delay: 0.14)
            ScrollView {
                VStack(spacing: 10) {
                    languageRow(
                        code: nil,
                        name: "System",
                        detail: "Follows the system language",
                        percent: nil,
                        selected: selected == nil
                    )
                    ForEach(orderedCodes, id: \.self) { code in
                        languageRow(
                            code: code,
                            name: AppLanguage.nativeName(code),
                            detail: nil,
                            percent: percent(of: code),
                            selected: selected == code
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .padding(.top, 20)
            .riseIn(delay: 0.2)
            PillButton("Continue", action: onNext)
                .riseIn(delay: 0.3)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            selected = AppLanguage.override
            rows = AppLocalizations.coverage()
        }
    }

    private func languageRow(
        code: String?,
        name: String,
        detail: String?,
        percent: Int?,
        selected: Bool
    ) -> some View {
        // Ganze Box klickbar: der Button umschließt die Karte, nicht umgekehrt.
        Button(action: {
            // Sofort anwenden: persistieren + laufender Prozess (kein Neustart).
            AppLanguage.set(code)
            self.selected = code
        }) {
            UberCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if selected {
                            Circle()
                                .fill(accent.resolved(scheme))
                                .frame(width: 12, height: 12)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(name)
                                .font(UberFont.text(15, weight: .heavy))
                                .tracking(-0.2)
                            Spacer()
                            if let percent {
                                Text("\(percent) %")
                                    .font(UberFont.text(13))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                        }
                        if let percent {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(EduFlowPalette.surface2(scheme))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(accent.resolved(scheme))
                                        .frame(width: geometry.size.width * CGFloat(percent) / 100, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        if let detail {
                            Text(detail)
                                .font(UberFont.text(13))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .riseIn(delay: 0.2)
    }
}

/// Seite 1: nur Logo mit Hallo-Animation (plus Weiter-Button).
public struct OnboardingWelcomePage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showButton = false
    @State private var greetings = AppLocalizations.greetings(fallback: ["Hallo!"])
    public let onNext: () -> Void

    public init(onNext: @escaping () -> Void) {
        self.onNext = onNext
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HelloGreeting(cycleGreetings: greetings)
            ZStack {
                if !reduceMotion {
                    SparkleView()
                        .opacity(0.6)
                        .blur(radius: 1)
                }
                AppLogo()
            }
            .frame(width: 320, height: 280)
            .padding(.top, 8)
            .riseIn(delay: 0.45)
            Spacer()
            PillButton("Continue", action: onNext)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 22)
                .scaleEffect(showButton ? 1 : 0.985)
                .task {
                    if reduceMotion {
                        showButton = true
                        return
                    }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation(
                        .timingCurve(0.22, 0.8, 0.32, 1.12, duration: 0.55)
                    ) {
                        showButton = true
                    }
                }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Seite 3: drei Funktions-Karten mit SF Symbols.
public struct OnboardingFeaturesPage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    public let onNext: () -> Void

    public init(onNext: @escaping () -> Void) {
        self.onNext = onNext
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Everything in one place.")
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-1.2)
                .padding(.top, 12)
                .riseIn(delay: 0.08)
            VStack(spacing: 10) {
                featureRow(icon: "envelope", title: NSLocalizedString("onboarding_feature_messages_title", value: "Messages & Threads", comment: "Onboarding: Nachrichten Titel"), text: NSLocalizedString("onboarding_feature_messages_text", value: "All EduPage messages in a mail layout — with likes, replies and files.", comment: "Onboarding: Nachrichten Beschreibung"), delay: 0.14)
                featureRow(icon: "checklist", title: NSLocalizedString("onboarding_feature_homework_title", value: "Homework & Grades", comment: "Onboarding: Aufgaben Titel"), text: NSLocalizedString("onboarding_feature_homework_text", value: "Due dates with counters, semester tabs and average.", comment: "Onboarding: Aufgaben Beschreibung"), delay: 0.2)
                featureRow(icon: "calendar", title: NSLocalizedString("onboarding_feature_timetable_title", value: "Timetable & Weather", comment: "Onboarding: Stundenplan Titel"), text: NSLocalizedString("onboarding_feature_timetable_text", value: "Day and week plus weather on the overview.", comment: "Onboarding: Stundenplan Beschreibung"), delay: 0.26)
            }
            .padding(.top, 22)
            Spacer()
            PillButton("Continue", action: onNext)
                .riseIn(delay: 0.32)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, title: String, text: String, delay: Double) -> some View {
        UberCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent.resolvedInk(scheme))
                    .frame(width: 40, height: 40)
                    .background(accent.resolved(scheme))
                    .clipShape(.capsule)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(UberFont.text(15, weight: .heavy))
                        .tracking(-0.2)
                    Text(text)
                        .font(UberFont.text(13))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .lineSpacing(2)
                }
            }
        }
        .riseIn(delay: delay)
    }
}

/// Seite 4: Server-URL (optional) mit Verbindungstest ohne Speichern.
public struct OnboardingServerPage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ServerCheckModel
    public let onNext: () -> Void

    public init(store: TokenStore, onNext: @escaping () -> Void) {
        _model = State(initialValue: ServerCheckModel(store: store))
        self.onNext = onNext
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Where does your server run?")
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-1.2)
                .padding(.top, 12)
                .riseIn(delay: 0.08)
            Text("Enter where EduFlow runs as server.")
                .font(UberFont.text(14))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.horizontal, 24)
                .riseIn(delay: 0.14)
            UberTextField(
                text: $model.url,
                placeholder: TokenStore.defaultBaseURL,
                icon: "server.rack"
            ) {
                Task {
                    await model.check()
                    if case .ok = model.result {
                        model.celebrate()
                    }
                }
            }
            .onChange(of: model.url) {
                model.resetResult()
            }
            .padding(.top, 20)
            .riseIn(delay: 0.2)
            Group {
                if case .failed(let message) = model.result {
                    Notice(message)
                        .foregroundStyle(EduFlowPalette.red)
                        .padding(.top, 10)
                } else if case .ok = model.result {
                    // Großer grüner Haken bei erfolgreichem Test —
                    // gleiche Sprache wie „EduFlow ist bereit".
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(EduFlowPalette.green)
                        .frame(height: 84)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Color.clear.frame(height: 84)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: model.result)
            Spacer()
            // Ein Knopf in voller Breite wie auf Seite 1 — die Prüfung
            // läuft beim Übernehmen automatisch (Fehler bleiben stehen).
            PillButton(model.checking ? "Checking connection …" : model.showSuccess ? "Connected" : "Apply & continue") {
                Task { @MainActor in
                    if await model.proceed(reduceMotion: reduceMotion) {
                        onNext()
                    }
                }
            }
            .disabled(model.checking || model.showSuccess)
            .riseIn(delay: 0.3)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // Erfolgs-Overlay über allem: abgedunkelte Seite plus
            // großer Haken auf weißer Plakette (blockiert kurz).
            if model.showSuccess {
                ZStack {
                    Color.black.opacity(0.25)
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.2), radius: 24)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 140, weight: .bold))
                            .foregroundStyle(EduFlowPalette.green)
                    }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .accessibilityHidden(true)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: model.showSuccess)
    }
}
