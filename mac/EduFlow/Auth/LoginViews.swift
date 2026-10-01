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
    private let totalSteps = 5

    public init(
        store: TokenStore,
        onTwoFA: @escaping (String) -> Void,
        onLoggedIn: @escaping (Route) -> Void
    ) {
        self.store = store
        self.onTwoFA = onTwoFA
        self.onLoggedIn = onLoggedIn
        _vm = State(initialValue: LoginViewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AppLogo()
                Text("EduFlow")
                    .font(UberFont.text(28, weight: .heavy))
                    .tracking(-0.8)
                    .padding(.top, 20)
                stepDots
                    .padding(.top, 12)
                Text(String(format: NSLocalizedString("auth_step_counter", value: "Step %d of %d", comment: "Anmeldung: Schrittzähler"), step + 1, totalSteps))
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                if let error = vm.error {
                    Notice(error.message)
                        .padding(.bottom, 6)
                }
                stepContent
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                navRow
                    .padding(.top, 22)
                if step == totalSteps - 1 {
                    PillButton(vm.isLoading ? "Signing in …" : "Sign in") {
                        doLogin()
                    }
                    .disabled(vm.isLoading)
                    .padding(.top, 12)
                    Text("Local tool — credentials stay on this Mac.")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 18)
                }
                if store.isDemo {
                    Text("Demo mode · synthetic sample data only")
                        .font(UberFont.text(12, weight: .semibold))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    Button("Leave demo") { vm.stopDemo() }
                        .font(UberFont.text(13, weight: .bold))
                        .padding(.top, 4)
                } else {
                    Button("View demo") { startDemo() }
                        .font(UberFont.text(13, weight: .bold))
                        .padding(.top, 10)
                }
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("auth_nav_login", value: "Sign in", comment: "Anmeldung: Titel"))
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
            stepHint(NSLocalizedString("auth_hint_school", value: "Which school do you belong to?", comment: "Anmeldung: Schulhinweis"))
            AuthLabel(NSLocalizedString("auth_label_subdomain", value: "Subdomain (optional)", comment: "Anmeldung: Subdomain-Label"))
            UberTextField(
                text: $vm.subdomain,
                placeholder: NSLocalizedString("auth_placeholder_subdomain", value: "e.g. musterschule", comment: "Anmeldung: Subdomain-Platzhalter"),
                icon: "building.2",
                autofocus: true
            ) { advance() }
            .onChange(of: vm.subdomain) { vm.clearError() }
        case 1:
            stepHint(NSLocalizedString("auth_hint_username", value: "What is your EduPage username?", comment: "Anmeldung: Benutzerhinweis"))
            AuthLabel(NSLocalizedString("auth_label_username", value: "Username", comment: "Anmeldung: Benutzername-Label"))
            UberTextField(
                text: $vm.username,
                placeholder: NSLocalizedString("auth_placeholder_username", value: "e.g. max.muster", comment: "Anmeldung: Benutzername-Platzhalter"),
                icon: "person",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.username) { vm.clearError() }
        case 2:
            stepHint(NSLocalizedString("auth_hint_password", value: "And your password?", comment: "Anmeldung: Passworthinweis"))
            AuthLabel(NSLocalizedString("auth_label_password", value: "Password", comment: "Anmeldung: Passwort-Label"))
            UberSecureField(
                text: $vm.password,
                placeholder: NSLocalizedString("auth_placeholder_password", value: "Enter password", comment: "Anmeldung: Passwort-Platzhalter"),
                icon: "lock",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.password) { vm.clearError() }
        case 3:
            stepHint(NSLocalizedString("auth_hint_device", value: "Which device are you signing in?", comment: "Anmeldung: Gerätehinweis"))
            AuthLabel(NSLocalizedString("auth_label_device", value: "Device (optional)", comment: "Anmeldung: Gerät-Label"))
            UberTextField(
                text: $vm.device,
                placeholder: NSLocalizedString("auth_placeholder_device", value: "e.g. MacBook", comment: "Anmeldung: Gerät-Platzhalter"),
                icon: "desktopcomputer",
                autofocus: true
            ) { advance() }
        default:
            stepHint(NSLocalizedString("Where does your server run?", value: "Where does your server run?", comment: "Anmeldung: Serverhinweis"))
            AuthLabel(NSLocalizedString("auth_label_server", value: "Server URL", comment: "Anmeldung: Server-Label"))
            UberTextField(
                text: $vm.baseURL,
                placeholder: TokenStore.defaultBaseURL,
                icon: "server.rack",
                autofocus: true
            ) { doLogin() }
            Button("Apply") { vm.applyBaseURL() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 4)
            Text(String(format: NSLocalizedString("auth_server_line", value: "Server: %@", comment: "Anmeldung: Serverzeile"), vm.baseURL))
                .font(UberFont.text(12))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
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
                Button("Back") { go(to: step - 1) }
                    .font(UberFont.text(14, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
            Spacer()
            if step < totalSteps - 1 {
                PillButton("Continue", style: .smallPrimary) { advance() }
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

    public init(
        store: TokenStore,
        pendingToken: String,
        onLoggedIn: @escaping (Route) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.pendingToken = pendingToken
        self.onLoggedIn = onLoggedIn
        self.onBack = onBack
        _vm = State(initialValue: TwoFAViewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandMark()
                Text("Enter code")
                    .font(UberFont.text(28, weight: .heavy))
                    .tracking(-0.8)
                    .padding(.top, 20)
                Text("Enter the code from your email or app.")
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
                    placeholder: NSLocalizedString("auth_placeholder_code", value: "6-digit code", comment: "Anmeldung: Code-Platzhalter"),
                    icon: "key",
                    isError: vm.error != nil,
                    autofocus: true,
                    allowReveal: false
                ) { doSubmit() }
                .onChange(of: vm.code) { vm.clearError() }
                PillButton(vm.isLoading ? "Checking …" : "Confirm") {
                    doSubmit()
                }
                .disabled(vm.isLoading || vm.code.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 22)
                Button("Back to sign-in", action: onBack)
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
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("auth_nav_2fa", value: "Two-factor code", comment: "Anmeldung: 2FA-Titel"))
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
