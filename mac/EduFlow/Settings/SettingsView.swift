import SwiftUI

/// Einstellungen wie `/einstellungen`: Karten-Abschnitte mit Titel,
/// Radio-Cards für Startseite und Filter, Schalter, Stufen, Akzent-Dots,
/// Server-URL, Cache und Abmelden (nie Sackgasse).
public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(TokenStore.self) private var store
    @State private var vm: SettingsViewModel
    @State private var accent = Accent.stored
    @AppStorage("de.eduflow.developerOptionsEnabledV1") private var developerOptionsEnabled = false
    private let onSessionExpired: () -> Void
    private let onDevices: () -> Void
    private let onLogout: () -> Void

    public init(
        store: TokenStore,
        onSessionExpired: @escaping () -> Void,
        onDevices: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        _vm = State(initialValue: SettingsViewModel(store: store))
        self.onSessionExpired = onSessionExpired
        self.onDevices = onDevices
        self.onLogout = onLogout
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead("Einstellungen")
                if vm.isLoading && vm.error == nil {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    startSection
                    homeworkSection
                    overviewSection
                    appearanceSection
                    serverSection
                    developerSection
                    if let error = vm.error {
                        Notice(error.message)
                    }
                    if let message = vm.clearMessage {
                        Text(message)
                            .font(UberFont.text(13))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    actionsSection
                }
            }
            .padding(20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("settings_nav", value: "Einstellungen", comment: "Einstellungen: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }

    // MARK: - Abschnitte

    private var startSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Startseite nach Anmeldung")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RadioCard(title: "Übersicht", desc: "Uhr, Nachrichten, Essen", value: "uebersicht", selection: $vm.values.landing)
                    RadioCard(title: "Nachrichten", desc: "Direkt in die Nachrichten", value: "dashboard", selection: $vm.values.landing)
                    RadioCard(title: "Hausaufgaben", desc: "Direkt zu den Aufgaben", value: "hausaufgaben", selection: $vm.values.landing)
                    RadioCard(title: "Noten", desc: "Direkt zu den Noten", value: "noten", selection: $vm.values.landing)
                    RadioCard(title: "Stundenplan", desc: "Direkt zum Stundenplan", value: "stundenplan", selection: $vm.values.landing)
                }
            }
        }
    }

    private var homeworkSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hausaufgaben")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Text("Standardfilter")
                    .font(UberFont.text(13, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RadioCard(title: "Alle", desc: "Alles zeigen", value: "alle", selection: $vm.values.hwStatus)
                    RadioCard(title: "Nur offene", desc: "Ohne erledigte", value: "offen", selection: $vm.values.hwStatus)
                    RadioCard(title: "Nur überfällige", desc: "Frist vorbei", value: "überfällig", selection: $vm.values.hwStatus)
                    RadioCard(title: "Nur erledigte", desc: "Fertige Aufgaben", value: "erledigt", selection: $vm.values.hwStatus)
                    RadioCard(title: "Papierkorb", desc: "Ausgeblendete", value: "papierkorb", selection: $vm.values.hwStatus)
                }
                Toggle("Tests und Prüfungen einbeziehen", isOn: $vm.values.hwTests)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))
            }
        }
    }

    private var overviewSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Übersicht")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Stepper(String(format: NSLocalizedString("settings_max_unread", value: "Max. ungelesene Nachrichten: %d", comment: "Einstellungen: ungelesene Nachrichten"), vm.values.ovUnread), value: $vm.values.ovUnread, in: 1...50)
                    .font(UberFont.text(14, weight: .medium))
                Stepper(String(format: NSLocalizedString("settings_max_homework", value: "Max. offene Hausaufgaben: %d", comment: "Einstellungen: offene Hausaufgaben"), vm.values.ovHomework), value: $vm.values.ovHomework, in: 1...50)
                    .font(UberFont.text(14, weight: .medium))
                Toggle("Wetterkarte anzeigen", isOn: $vm.values.ovWetter)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))
                TextField("Wetter: Stadt (optional)", text: $vm.values.wetterCity)
                    .uberInput()
                    .autocorrectionDisabled()
            }
        }
    }

    private var appearanceSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Aussehen")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Text("Hell und Dunkel folgt dem System. Akzentfarbe:")
                    .font(UberFont.text(13))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                HStack(spacing: 12) {
                    ForEach(Accent.allCases) { option in
                        Button {
                            accent = option
                            Accent.stored = option
                        } label: {
                            Circle()
                                .fill(option == .black ? EduFlowPalette.ink(scheme) : option.color)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                                }
                                .overlay {
                                    if accent == option {
                                        Circle()
                                            .stroke(EduFlowPalette.ink(scheme), lineWidth: 2)
                                            .padding(-4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .hoverLift()
                        .help(option.displayName)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var serverSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.isDemo ? "Demo-Modus" : "Server")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                if store.isDemo {
                    Text("Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.")
                        .font(UberFont.text(13))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                } else {
                    TextField("Basis-URL", text: $vm.baseURL)
                        .uberInput()
                        .autocorrectionDisabled()
                    Button("Übernehmen") { vm.applyBaseURL() }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                }
            }
        }
    }

    private var developerSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Entwickleroptionen")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Toggle("Entwickleroptionen aktivieren", isOn: $developerOptionsEnabled)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))

                if developerOptionsEnabled {
                    Toggle("Onboarding erneut durchlaufen", isOn: onboardingRestartBinding)
                        .font(UberFont.text(14, weight: .medium))
                        .tint(accent.resolved(scheme))
                        .disabled(vm.isLoggingOut)
                    Text("Meldet dich ab und startet die Einführung erneut.")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                }
            }
        }
    }

    /// Der zweite Schalter ist eine Aktion und springt danach zurück auf Aus.
    private var onboardingRestartBinding: Binding<Bool> {
        Binding(
            get: { false },
            set: { shouldRestart in
                guard shouldRestart, !vm.isLoggingOut else { return }
                OnboardingState.reset()
                Task {
                    await vm.logout()
                    onLogout()
                }
            }
        )
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            PillButton(vm.isSaving ? "Speichern …" : "Speichern") {
                Task { await vm.save(onSessionExpired: onSessionExpired) }
            }
            .disabled(vm.isSaving || vm.isLoading)
            HStack(spacing: 10) {
                Button("Erneut laden") {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                .disabled(vm.isLoading)
                Button(vm.isClearing ? NSLocalizedString("settings_cache_clear_busy", value: "Cache leeren …", comment: "Einstellungen: Cache leeren läuft") : NSLocalizedString("settings_cache_clear", value: "Cache leeren", comment: "Einstellungen: Cache leeren")) {
                    Task { await vm.clearCache(onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                .disabled(vm.isClearing)
                Button("Geräte verwalten", action: onDevices)
                    .buttonStyle(UberButtonStyle(.smallLight))
                    .hoverLift()
            }
            Button(vm.isLoggingOut ? "Abmelden …" : "Abmelden") {
                Task {
                    await vm.logout()
                    onLogout()
                }
            }
            .buttonStyle(UberButtonStyle(.smallLight))
            .hoverLift()
            .disabled(vm.isLoggingOut)
            .foregroundStyle(EduFlowPalette.red)
        }
    }
}

/// Radio-Karte (`.radio-card`): gewählt mit Tinten-Rahmen und Fläche.
private struct RadioCard: View {
    @Environment(\.colorScheme) var scheme
    @State private var hovering = false
    let title: String
    let desc: String
    let value: String
    @Binding var selection: String

    var body: some View {
        Button {
            selection = value
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(UberFont.text(14, weight: .heavy))
                Text(desc)
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                selection == value ? EduFlowPalette.surface1(scheme)
                    : (hovering ? EduFlowPalette.surface1(scheme) : Color.clear)
            )
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        EduFlowPalette.ink(scheme),
                        lineWidth: selection == value ? 2 : 0
                    )
            }
            .overlay {
                if selection != value {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
