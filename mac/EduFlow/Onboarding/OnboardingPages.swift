import AppKit
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
            result = .failed(message: APIError.germanFallback(for: ErrorCodes.upstream))
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

/// Seite 1: nur Logo mit Hallo-Animation (plus Weiter-Button).
public struct OnboardingWelcomePage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showButton = false
    public let onNext: () -> Void

    public init(onNext: @escaping () -> Void) {
        self.onNext = onNext
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HelloGreeting()
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
            PillButton("Weiter", action: onNext)
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

/// Seite 2: drei Funktions-Karten mit SF Symbols.
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
            Text("Alles an einem Ort.")
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-1.2)
                .padding(.top, 12)
                .riseIn(delay: 0.08)
            VStack(spacing: 10) {
                featureRow(icon: "envelope", title: "Nachrichten & Threads", text: "Alle EduPage-Nachrichten im Mail-Layout — mit Likes, Antworten und Dateien.", delay: 0.14)
                featureRow(icon: "checklist", title: "Hausaufgaben & Noten", text: "Fälligkeiten mit Zählern, Halbjahr-Tabs und Schnitt.", delay: 0.2)
                featureRow(icon: "calendar", title: "Stundenplan, Essen & Wetter", text: "Tag und Woche, Mensa-Plan und Wetter auf der Übersicht.", delay: 0.26)
            }
            .padding(.top, 22)
            Spacer()
            PillButton("Weiter", action: onNext)
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

/// Seite 3: Server-URL (optional) mit Verbindungstest ohne Speichern.
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
            Text("Wo läuft dein Server?")
                .font(UberFont.text(30, weight: .heavy))
                .tracking(-1.2)
                .padding(.top, 12)
                .riseIn(delay: 0.08)
            Text("Trage ein, wo EduFlow als Server läuft.")
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
            PillButton(model.checking ? "Prüft …" : model.showSuccess ? "Verbunden" : "Übernehmen & weiter") {
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
