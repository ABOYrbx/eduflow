import AppKit
import SwiftUI

/// Eigene App-Hülle ohne System-Sidebar: schwebende Pillen-Navigation
/// im Web-Stil (`.nav-wrap`) oben, Inhalt darunter. Onboarding und
/// Login laufen fensterfüllend ohne Navigation.
///
/// Das Fenster ist nur im Onboarding klein und fix (400×600, nicht
/// skalierbar, wie das boring.notch-Onboarding). Danach ist es normal
/// groß und frei skalierbar (siehe `WindowChrome`).
private enum AppWindow {
    static let width: CGFloat = 400
    static let height: CGFloat = 600
}

/// Normale Fenstergröße nach dem Onboarding (frei skalierbar).
private enum AppHome {
    static let width: CGFloat = 1150
    static let height: CGFloat = 780
    static let minWidth: CGFloat = 900
    static let minHeight: CGFloat = 600
}

struct ContentView: View {
    @Environment(TokenStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var selection: Route?

    private var isOnboarding: Bool {
        OnboardingState.shouldShow(isLoggedIn: store.isLoggedIn)
    }

    var body: some View {
        Group {
            if isOnboarding {
                OnboardingFlow(store: store, onLoggedIn: { selection = $0 })
                    .frame(width: AppWindow.width, height: AppWindow.height)
            } else if store.isLoggedIn {
                VStack(spacing: 0) {
                    TopPillNav(
                        selection: selection,
                        store: store,
                        onNavigate: { selection = $0 },
                        onLogout: logout
                    )
                    detailView(for: selection ?? .overview)
                }
            } else {
                detailView(for: selection ?? .login)
            }
        }
        .background(WindowChrome(isOnboarding: isOnboarding))
        .background(EduFlowPalette.canvas(scheme))
        .onAppear {
            if selection == nil {
                selection = store.isLoggedIn ? .overview : .login
            }
        }
        .onChange(of: store.isLoggedIn) { _, loggedIn in
            selection = loggedIn ? .overview : .login
        }
    }

    /// Abmelden: serverseitig best-effort, lokal immer.
    private func logout() {
        Task {
            try? await AuthRepository(client: store.makeClient()).logout()
            store.clear()
            selection = .login
        }
    }

    @ViewBuilder
    private func detailView(for route: Route) -> some View {
        switch route {
        case .login:
            LoginView(
                store: store,
                onTwoFA: { selection = .twoFA(pending: $0) },
                onLoggedIn: { selection = $0 }
            )
        case .twoFA(let pending):
            TwoFAView(
                store: store,
                pendingToken: pending,
                onLoggedIn: { selection = $0 },
                onBack: { selection = .login }
            )
        case .overview:
            OverviewView(
                store: store,
                onNavigate: { selection = $0 },
                onSessionExpired: { selection = .login }
            )
        case .messages:
            MessagesView(
                store: store,
                onThread: { selection = .thread(message: $0) },
                onCompose: { selection = .compose },
                onSessionExpired: { selection = .login }
            )
        case .thread(let message):
            ThreadView(
                store: store,
                message: message,
                onBack: { selection = .messages },
                onSessionExpired: { selection = .login }
            )
        case .compose:
            ComposeView(
                store: store,
                onSent: { selection = .messages },
                onSessionExpired: { selection = .login }
            )
        case .homework:
            HomeworkView(
                store: store,
                onSessionExpired: { selection = .login }
            )
        case .timetable:
            DayView(
                store: store,
                onSessionExpired: { selection = .login }
            )
        case .school:
            SchoolView(
                store: store,
                onSessionExpired: { selection = .login }
            )
        case .grades:
            GradesView(
                store: store,
                onSessionExpired: { selection = .login }
            )
        case .settings:
            SettingsView(
                store: store,
                onSessionExpired: { selection = .login },
                onDevices: { selection = .devices },
                onLogout: { selection = .login }
            )
        case .devices:
            DevicesView(
                store: store,
                onSessionExpired: { selection = .login }
            )
        }
    }
}

/// Obere Navigationsleiste im App-Fenster: Brand, Abschnitts-Pillen,
/// Avatar-Menü. Die Leiste sitzt direkt am oberen Fensterrand.
private struct TopPillNav: View {
    @Environment(\.colorScheme) var scheme
    @State private var profileMenuOpen = false
    let selection: Route?
    let store: TokenStore
    let onNavigate: (Route) -> Void
    let onLogout: () -> Void

    /// Aktiver Abschnitt: Thread und Verfassen gehören zu Nachrichten,
    /// der Rest mappt auf sich selbst (Einstellungen/Geräte/Login → nichts).
    private var activeSection: Route? {
        switch selection {
        case .thread, .compose:
            .messages
        case .overview, .messages, .homework, .grades, .timetable, .school:
            selection
        default:
            nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                BrandMark()
                    .padding(.leading, 4)
                if store.isDemo {
                    Text("DEMO")
                        .font(UberFont.text(10, weight: .heavy))
                        .tracking(0.6)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(EduFlowPalette.surface2(scheme))
                        .clipShape(.capsule)
                        .help(NSLocalizedString("content_demo_hint", value: "Nur synthetische Beispieldaten vom lokalen Fake-Server", comment: "Navigation: Demo-Hinweis"))
                }
                NavPill(title: "Übersicht", active: activeSection == .overview) {
                    onNavigate(.overview)
                }
                NavPill(title: "Nachrichten", active: activeSection == .messages) {
                    onNavigate(.messages)
                }
                NavPill(title: "Hausaufgaben", active: activeSection == .homework) {
                    onNavigate(.homework)
                }
                NavPill(title: "Noten", active: activeSection == .grades) {
                    onNavigate(.grades)
                }
                NavPill(title: "Stundenplan", active: activeSection == .timetable) {
                    onNavigate(.timetable)
                }
                NavPill(title: "Termine", active: activeSection == .school) {
                    onNavigate(.school)
                }
                avatarMenu
                    .padding(.trailing, 4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
            .clipShape(.capsule)
            .overlay {
                Capsule()
                    .stroke(.white.opacity(scheme == .dark ? 0.14 : 0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.14), radius: 40, y: 12)
            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .padding(.horizontal, 16)
    }

    /// Avatar mit Profilmenü wie `.profile-menu` (Einstellungen, Geräte, Abmelden).
    private var avatarMenu: some View {
        Button { profileMenuOpen.toggle() } label: {
            Text(String(store.username.prefix(1).uppercased()))
                .font(UberFont.text(15, weight: .heavy))
                .frame(width: 38, height: 38)
                .background(EduFlowPalette.surface2(scheme))
                .foregroundStyle(EduFlowPalette.ink(scheme))
                .clipShape(.circle)
                .overlay(Circle().stroke(EduFlowPalette.border(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("common_profile_menu_open", value: "Profilmenü öffnen", comment: "Navigation: Profilmenü"))
        .help("\(store.username) @ \(store.subdomain)")
        .popover(isPresented: $profileMenuOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(verbatim: String(store.username.prefix(1).uppercased()))
                        .font(UberFont.text(16, weight: .heavy))
                        .frame(width: 42, height: 42)
                        .background(EduFlowPalette.surface2(scheme))
                        .foregroundStyle(EduFlowPalette.ink(scheme))
                        .clipShape(.circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dein Profil").font(UberFont.text(14, weight: .bold))
                        Text(verbatim: "\(store.username) @ \(store.subdomain)")
                            .font(UberFont.text(12))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                }
                Divider()
                profileAction("Einstellungen", icon: "gearshape") {
                    profileMenuOpen = false
                    onNavigate(.settings)
                }
                profileAction("Geräte", icon: "laptopcomputer.and.iphone") {
                    profileMenuOpen = false
                    onNavigate(.devices)
                }
                Divider()
                profileAction("Abmelden", icon: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                    profileMenuOpen = false
                    onLogout()
                }
            }
            .padding(16)
            .frame(width: 280, alignment: .leading)
            .background(EduFlowPalette.canvas(scheme))
        }
    }

    private func profileAction(
        _ title: String,
        icon: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(UberFont.text(13, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : EduFlowPalette.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Abschnitts-Pille wie `.nav-pill`, größer für Desktop: 15px/600, aktiv mit Fläche.
private struct NavPill: View {
    @Environment(\.colorScheme) var scheme
    @State private var hovering = false
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(UberFont.text(15, weight: .semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .foregroundStyle(active || hovering ? EduFlowPalette.ink(scheme) : EduFlowPalette.inkMuted(scheme))
                .background(active ? EduFlowPalette.surface2(scheme) : (hovering ? EduFlowPalette.surface1(scheme) : Color.clear))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Das Fenster bleibt ohne separate Titelleiste. Die Ampel-Knöpfe sind nur
/// während des Onboardings verborgen und erscheinen danach wieder.
///
/// Größen-Modi: Im Onboarding ist das Fenster klein und fixiert
/// (400×600, nicht skalierbar). Danach wird es auf Normalgröße
/// gebracht und ist frei skalierbar (mit Mindestgröße).
private struct WindowChrome: NSViewRepresentable {
    let isOnboarding: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let onboarding = isOnboarding
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = onboarding
            }
            if onboarding {
                window.styleMask.remove(.resizable)
                window.setContentSize(NSSize(width: AppWindow.width, height: AppWindow.height))
                center(window)
                context.coordinator.lastOnboarding = true
            } else {
                if !window.styleMask.contains(.resizable) {
                    window.styleMask.insert(.resizable)
                }
                window.minSize = NSSize(width: AppHome.minWidth, height: AppHome.minHeight)
                if context.coordinator.lastOnboarding == true {
                    window.setContentSize(NSSize(width: AppHome.width, height: AppHome.height))
                    center(window)
                }
                context.coordinator.lastOnboarding = false
            }
        }
    }

    private func center(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    final class Coordinator {
        var lastOnboarding: Bool?
    }
}
