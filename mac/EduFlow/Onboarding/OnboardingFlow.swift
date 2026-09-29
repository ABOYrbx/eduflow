import Combine
import Foundation
import SwiftUI

/// Onboarding-Ablauf (nur erster Start): Willkommen → Sprache →
/// Funktionen → Server (optional) → Anmelden. Die Anmeldung ist die
/// bestehende Login-Ansicht inklusive Zwei-Faktor-Pfad; bei Erfolg wird das
/// Flag gesetzt und zur Landing-Route navigiert.
///
/// Die Sprachwahl auf Seite 2 wirkt sofort (locale-Umgebung, kein
/// Neustart) — die Seite wird dabei NICHT neu aufgebaut, damit keine
/// Einstiegs-Animationen erneut abspielen und die Liste nicht springt.
public struct OnboardingFlow: View {
    @Environment(\.colorScheme) private var scheme
    @State private var page = 0
    @State private var pending2FA: String?
    @State private var languageID = AppLanguage.current
    private let store: TokenStore
    private let onLoggedIn: (Route) -> Void

    public init(store: TokenStore, onLoggedIn: @escaping (Route) -> Void) {
        self.store = store
        self.onLoggedIn = onLoggedIn
    }

    public var body: some View {
        ZStack {
            // Partikel über die ganze App während des Onboardings —
            // einfach im Hintergrund auf allen Seiten (dieser Flow
            // existiert nach dem Onboarding nicht).
            OnboardingParticleBackground()
            Group {
                if let pending = pending2FA {
                    TwoFAView(
                        store: store,
                        pendingToken: pending,
                        onLoggedIn: finish,
                        onBack: { pending2FA = nil },
                        transparentBackground: true
                    )
                    .padding(20)
                } else {
                    VStack(spacing: 0) {
                        // Bewusst nur page als ID: Bei Sprachwechsel ändert
                        // sich nur die locale-Umgebung (Texte rendern neu),
                        // die Ansicht bleibt bestehen — sonst würde jeder
                        // Tap die RiseIn-Animationen erneut abspielen.
                        pageView(for: page)
                            .id(page)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EduFlowPalette.canvas(scheme))
        .environment(\.locale, Locale(identifier: languageID))
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            languageID = AppLanguage.current
        }
    }

    private func go(to index: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            page = index
        }
    }

    @ViewBuilder
    private func pageView(for index: Int) -> some View {
        switch index {
        case 0:
            OnboardingWelcomePage { go(to: 1) }
        case 1:
            OnboardingLanguagePage { go(to: 2) }
        case 2:
            OnboardingFeaturesPage { go(to: 3) }
        case 3:
            OnboardingServerPage(store: store) { go(to: 4) }
        default:
            LoginView(
                store: store,
                onTwoFA: { pending2FA = $0 },
                onLoggedIn: finish,
                showsServerStep: false,
                transparentBackground: true,
                onboardingLayout: true
            )
        }
    }

    private func finish(_ route: Route) {
        OnboardingState.complete()
        onLoggedIn(route)
    }
}
