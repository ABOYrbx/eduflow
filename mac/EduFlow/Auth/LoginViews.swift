import SwiftUI

/// Anmeldung direkt auf dem Hintergrund (ohne Karte): Brand-Zeichen,
/// Titel, Felder als Pillen, Server-URL mit Anzeige ohne Rebuild.
public struct LoginView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @State private var vm: LoginViewModel
    @State private var step = 0
    private let store: TokenStore
    private let onTwoFA: (String) -> Void
    private let onLoggedIn: (Route) -> Void
    /// Im Onboarding `false`: Der Server wurde dort bereits auf der
    /// eigenen Seite abgefragt — der letzte Schritt zeigt stattdessen
    /// eine „EduFlow ist bereit“-Animation.
    private let showsServerStep: Bool
    /// Im Onboarding `true`: kein opaker Hintergrund, damit die
    /// Onboarding-Partikel durchscheinen.
    private let transparentBackground: Bool
    /// Im Onboarding `true`: exakt dasselbe Seitenmuster wie die
    /// anderen Onboarding-Schritte (Spacer oben/unten, kein Scrollen,
    /// 560er-Breite) statt der eigenständigen Login-Darstellung.
    private let onboardingLayout: Bool
    private let totalSteps = 5

    public init(
        store: TokenStore,
        onTwoFA: @escaping (String) -> Void,
        onLoggedIn: @escaping (Route) -> Void,
        showsServerStep: Bool = true,
        transparentBackground: Bool = false,
        onboardingLayout: Bool = false
    ) {
        self.store = store
        self.onTwoFA = onTwoFA
        self.onLoggedIn = onLoggedIn
        self.showsServerStep = showsServerStep
        self.transparentBackground = transparentBackground
        self.onboardingLayout = onboardingLayout
        _vm = State(initialValue: LoginViewModel(store: store))
    }

    public var body: some View {
        Group {
            if onboardingLayout {
                // Gleiches Muster wie Willkommen/Funktionen/Server:
                // Inhalt zwischen zwei Spacern, der Primärknopf
                // („Weiter"/„Anmelden") als letztes Element ganz unten —
                // exakt wie auf Schritt 1. Zurück/Demo fahren im
                // Mittelblock mit und verschieben ihn nicht.
                VStack(spacing: 0) {
                    Spacer()
                    loginHeader
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    onboardingSecondary
                    Spacer()
                    PillButton(primaryTitle) {
                        advance()
                    }
                    .disabled(primaryDisabled)
                    .riseIn(delay: 0.3)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            loginHeader
                            stepContent
                                .id(step)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                        .padding(.top, 36)
                        .padding(.horizontal, 32)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)
                    }
                    // Button-Block fest am unteren Rand — außerhalb
                    // der Scroll-Ansicht.
                    loginButtons
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(transparentBackground ? Color.clear : EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("auth_nav_login", value: "Anmelden", comment: "Anmeldung: Titel"))
    }

    /// Kopf: Logo, Titel, Schrittpunkte, Zähler und Fehlermeldung.
    @ViewBuilder
    private var loginHeader: some View {
        AppLogo()
        Text("EduFlow")
            .font(UberFont.text(28, weight: .heavy))
            .tracking(-0.8)
            .padding(.top, 20)
        stepDots
            .padding(.top, 12)
        Text(String(format: NSLocalizedString("auth_step_counter", value: "Schritt %d von %d", comment: "Anmeldung: Schrittzähler"), step + 1, totalSteps))
            .font(UberFont.text(12))
            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .padding(.top, 4)
            .padding(.bottom, 16)
        if let error = vm.error {
            Notice(error.message)
                .padding(.bottom, 6)
        }
    }

    /// Knöpfe: Zurück/Weiter, Anmelden am letzten Schritt, Demo.
    @ViewBuilder
    private var loginButtons: some View {
        navRow
        if step == totalSteps - 1 {
            PillButton(vm.isLoading ? "Anmelden …" : "Anmelden") {
                doLogin()
            }
            .disabled(vm.isLoading)
            .padding(.top, 12)
            Text("Lokales Werkzeug — Zugangsdaten bleiben auf diesem Mac.")
                .font(UberFont.text(12))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 18)
        }
        if store.isDemo {
            Text("Demo-Modus · nur synthetische Beispieldaten")
                .font(UberFont.text(12, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Button("Demo verlassen") { vm.stopDemo() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 4)
        } else {
            Button("Demo ansehen") { startDemo() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 10)
        }
    }

    /// Primärknopf-Titel im Onboarding: „Weiter" auf den Schritten,
    /// „Anmelden" auf dem letzten (`advance()` ruft dort den Login auf).
    private var primaryTitle: String {
        step == totalSteps - 1 ? (vm.isLoading ? "Anmelden …" : "Anmelden") : "Weiter"
    }

    private var primaryDisabled: Bool {
        step == totalSteps - 1 ? vm.isLoading : !canAdvance
    }

    /// Sekundärzeilen im Onboarding-Mittelblock: „Zurück" (auf Schritt 0
    /// unsichtbar, aber im Layout, damit nichts springt) plus Demo-Zeile.
    @ViewBuilder
    private var onboardingSecondary: some View {
        Button("Zurück") { go(to: step - 1) }
            .font(UberFont.text(14, weight: .bold))
            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)
            .accessibilityHidden(step == 0)
            .padding(.top, 14)
        if store.isDemo {
            Text("Demo-Modus · nur synthetische Beispieldaten")
                .font(UberFont.text(12, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Button("Demo verlassen") { vm.stopDemo() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 4)
        } else {
            Button("Demo ansehen") { startDemo() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 10)
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? accent.resolved(scheme) : EduFlowPalette.borderStrong(scheme))
                    .frame(width: index == step ? 24 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            stepHint(NSLocalizedString("auth_hint_school", value: "Zu welcher Schule gehörst du?", comment: "Anmeldung: Schulhinweis"))
            AuthLabel(NSLocalizedString("auth_label_subdomain", value: "Subdomain (optional)", comment: "Anmeldung: Subdomain-Label"))
            UberTextField(
                text: $vm.subdomain,
                placeholder: NSLocalizedString("auth_placeholder_subdomain", value: "z. B. musterschule", comment: "Anmeldung: Subdomain-Platzhalter"),
                icon: "building.2",
                autofocus: true
            ) { advance() }
            .onChange(of: vm.subdomain) { vm.clearError() }
        case 1:
            stepHint(NSLocalizedString("auth_hint_username", value: "Wie heißt du bei EduPage?", comment: "Anmeldung: Benutzerhinweis"))
            AuthLabel(NSLocalizedString("auth_label_username", value: "Benutzername", comment: "Anmeldung: Benutzername-Label"))
            UberTextField(
                text: $vm.username,
                placeholder: NSLocalizedString("auth_placeholder_username", value: "z. B. max.muster", comment: "Anmeldung: Benutzername-Platzhalter"),
                icon: "person",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.username) { vm.clearError() }
        case 2:
            stepHint(NSLocalizedString("auth_hint_password", value: "Und dein Passwort?", comment: "Anmeldung: Passworthinweis"))
            AuthLabel(NSLocalizedString("auth_label_password", value: "Passwort", comment: "Anmeldung: Passwort-Label"))
            UberSecureField(
                text: $vm.password,
                placeholder: NSLocalizedString("auth_placeholder_password", value: "Passwort eingeben", comment: "Anmeldung: Passwort-Platzhalter"),
                icon: "lock",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.password) { vm.clearError() }
        case 3:
            stepHint(NSLocalizedString("auth_hint_device", value: "Welches Gerät meldest du an?", comment: "Anmeldung: Gerätehinweis"))
            AuthLabel(NSLocalizedString("auth_label_device", value: "Gerät (optional)", comment: "Anmeldung: Gerät-Label"))
            UberTextField(
                text: $vm.device,
                placeholder: NSLocalizedString("auth_placeholder_device", value: "z. B. MacBook", comment: "Anmeldung: Gerät-Platzhalter"),
                icon: "desktopcomputer",
                autofocus: true
            ) { advance() }
        default:
            if showsServerStep {
                stepHint(NSLocalizedString("Wo läuft dein Server?", value: "Wo läuft dein Server?", comment: "Anmeldung: Serverhinweis"))
                AuthLabel(NSLocalizedString("auth_label_server", value: "Server-URL", comment: "Anmeldung: Server-Label"))
                UberTextField(
                    text: $vm.baseURL,
                    placeholder: TokenStore.defaultBaseURL,
                    icon: "server.rack",
                    autofocus: true
                ) { doLogin() }
                Button("Übernehmen") { vm.applyBaseURL() }
                    .font(UberFont.text(13, weight: .bold))
                    .padding(.top, 4)
                Text(String(format: NSLocalizedString("auth_server_line", value: "Server: %@", comment: "Anmeldung: Serverzeile"), vm.baseURL))
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            } else {
                ReadyStep()
                    .padding(.top, 4)
            }
        }
    }

    private func stepHint(_ text: String) -> some View {
        Text(text)
            .font(UberFont.text(14))
            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
    }

    private var canAdvance: Bool {
        switch step {
        case 1:
            return !vm.username.trimmingCharacters(in: .whitespaces).isEmpty
        case 2:
            return !vm.password.isEmpty
        default:
            return true
        }
    }

    private func advance() {
        if step < totalSteps - 1 {
            go(to: step + 1)
        } else {
            doLogin()
        }
    }

    private func go(to index: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = min(max(index, 0), totalSteps - 1)
        }
    }

    private var navRow: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Zurück") { go(to: step - 1) }
                    .font(UberFont.text(14, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
            Spacer()
            if step < totalSteps - 1 {
                PillButton("Weiter") { advance() }
                    .disabled(!canAdvance)
            }
        }
    }

    private func doLogin() {
        Task {
            if let action = await vm.login() {
                switch action {
                case .twoFA(let pending): onTwoFA(pending)
                case .loggedIn(let route): onLoggedIn(route)
                }
            }
        }
    }

    private func startDemo() {
        Task {
            guard let action = await vm.startDemo() else { return }
            switch action {
            case .twoFA(let pending): onTwoFA(pending)
            case .loggedIn(let route): onLoggedIn(route)
            }
        }
    }
}

/// Zwei-Faktor direkt auf dem Hintergrund: Code-Feld plus Bestätigen.
public struct TwoFAView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: TwoFAViewModel
    private let pendingToken: String
    private let onLoggedIn: (Route) -> Void
    private let onBack: () -> Void
    /// Im Onboarding `true`: kein opaker Hintergrund, damit die
    /// Onboarding-Partikel durchscheinen.
    private let transparentBackground: Bool

    public init(
        store: TokenStore,
        pendingToken: String,
        onLoggedIn: @escaping (Route) -> Void,
        onBack: @escaping () -> Void,
        transparentBackground: Bool = false
    ) {
        self.pendingToken = pendingToken
        self.onLoggedIn = onLoggedIn
        self.onBack = onBack
        self.transparentBackground = transparentBackground
        _vm = State(initialValue: TwoFAViewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandMark()
                Text("Code eingeben")
                    .font(UberFont.text(28, weight: .heavy))
                    .tracking(-0.8)
                    .padding(.top, 20)
                Text("Code aus E-Mail oder App eingeben.")
                    .font(UberFont.text(14))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                if let error = vm.error {
                    Notice(error.message)
                        .padding(.bottom, 6)
                }
                AuthLabel(NSLocalizedString("auth_label_code", value: "Code", comment: "Anmeldung: Code-Label"))
                UberSecureField(
                    text: $vm.code,
                    placeholder: NSLocalizedString("auth_placeholder_code", value: "6-stelliger Code", comment: "Anmeldung: Code-Platzhalter"),
                    icon: "key",
                    isError: vm.error != nil,
                    autofocus: true,
                    allowReveal: false
                ) { doSubmit() }
                .onChange(of: vm.code) { vm.clearError() }
                PillButton(vm.isLoading ? "Prüfen …" : "Bestätigen") {
                    doSubmit()
                }
                .disabled(vm.isLoading || vm.code.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 22)
                Button("Zurück zur Anmeldung", action: onBack)
                    .font(UberFont.text(13, weight: .bold))
                    .padding(.top, 12)
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(transparentBackground ? Color.clear : EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("auth_nav_2fa", value: "Zwei-Faktor-Code", comment: "Anmeldung: 2FA-Titel"))
    }

    private func doSubmit() {
        Task {
            if let route = await vm.submit(pendingToken: pendingToken) {
                onLoggedIn(route)
            }
        }
    }
}

/// Feld-Label in der Auth-Karte.
private struct AuthLabel: View {
    @Environment(\.colorScheme) var scheme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(UberFont.text(13, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

/// Letzter Login-Schritt im Onboarding (statt erneuter Server-Abfrage):
/// aufpoppendes Häkchen mit pulsierendem Ring — „EduFlow ist bereit“.
private struct ReadyStep: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(EduFlowPalette.green.opacity(0.12))
                    .frame(width: 104, height: 104)
                    .scaleEffect(pulse ? 1.1 : 0.95)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(EduFlowPalette.green)
                    .scaleEffect(popped ? 1 : 0.4)
                    .opacity(popped ? 1 : 0)
            }
            .frame(height: 128)
            Text("EduFlow ist bereit")
                .font(UberFont.text(22, weight: .heavy))
                .tracking(-0.5)
            Text("Server, Schule und Gerät sind eingetragen.\nJetzt nur noch anmelden.")
                .font(UberFont.text(14))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .task {
            if reduceMotion {
                popped = true
                pulse = true
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                popped = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
