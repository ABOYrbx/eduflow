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
                Text("Schritt \(step + 1) von \(totalSteps)")
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
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Anmelden")
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
            stepHint("Zu welcher Schule gehörst du?")
            AuthLabel("Subdomain (optional)")
            UberTextField(
                text: $vm.subdomain,
                placeholder: "z. B. musterschule",
                icon: "building.2",
                autofocus: true
            ) { advance() }
            .onChange(of: vm.subdomain) { vm.clearError() }
        case 1:
            stepHint("Wie heißt du bei EduPage?")
            AuthLabel("Benutzername")
            UberTextField(
                text: $vm.username,
                placeholder: "z. B. max.muster",
                icon: "person",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.username) { vm.clearError() }
        case 2:
            stepHint("Und dein Passwort?")
            AuthLabel("Passwort")
            UberSecureField(
                text: $vm.password,
                placeholder: "Passwort eingeben",
                icon: "lock",
                isError: vm.error != nil,
                autofocus: true
            ) { advance() }
            .onChange(of: vm.password) { vm.clearError() }
        case 3:
            stepHint("Welches Gerät meldest du an?")
            AuthLabel("Gerät (optional)")
            UberTextField(
                text: $vm.device,
                placeholder: "z. B. MacBook",
                icon: "desktopcomputer",
                autofocus: true
            ) { advance() }
        default:
            stepHint("Wo läuft dein Server?")
            AuthLabel("Server-URL")
            UberTextField(
                text: $vm.baseURL,
                placeholder: TokenStore.defaultBaseURL,
                icon: "server.rack",
                autofocus: true
            ) { doLogin() }
            Button("Übernehmen") { vm.applyBaseURL() }
                .font(UberFont.text(13, weight: .bold))
                .padding(.top, 4)
            Text("Server: \(vm.baseURL)")
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
                Button("Zurück") { go(to: step - 1) }
                    .font(UberFont.text(14, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
            Spacer()
            if step < totalSteps - 1 {
                PillButton("Weiter", style: .smallPrimary) { advance() }
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
                AuthLabel("Code")
                UberSecureField(
                    text: $vm.code,
                    placeholder: "6-stelliger Code",
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
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Zwei-Faktor-Code")
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
