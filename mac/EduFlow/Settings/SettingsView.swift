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
                    RadioCard(title: NSLocalizedString("Übersicht", value: "Übersicht", comment: "Einstellungen: Startseite Übersicht"), desc: NSLocalizedString("settings_landing_overview_desc", value: "Uhr, Nachrichten, Wetter", comment: "Einstellungen: Startseite Übersicht Beschreibung"), value: "uebersicht", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("messages_nav_list", value: "Nachrichten", comment: "Einstellungen: Startseite Nachrichten"), desc: NSLocalizedString("settings_landing_messages_desc", value: "Direkt in die Nachrichten", comment: "Einstellungen: Startseite Nachrichten Beschreibung"), value: "dashboard", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("Hausaufgaben", value: "Hausaufgaben", comment: "Einstellungen: Startseite Aufgaben"), desc: NSLocalizedString("settings_landing_homework_desc", value: "Direkt zu den Aufgaben", comment: "Einstellungen: Startseite Aufgaben Beschreibung"), value: "hausaufgaben", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("grades_nav", value: "Noten", comment: "Einstellungen: Startseite Noten"), desc: NSLocalizedString("settings_landing_grades_desc", value: "Direkt zu den Noten", comment: "Einstellungen: Startseite Noten Beschreibung"), value: "noten", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("Stundenplan", value: "Stundenplan", comment: "Einstellungen: Startseite Stundenplan"), desc: NSLocalizedString("settings_landing_timetable_desc", value: "Direkt zum Stundenplan", comment: "Einstellungen: Startseite Stundenplan Beschreibung"), value: "stundenplan", selection: $vm.values.landing)
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
                    RadioCard(title: NSLocalizedString("homework_filter_all", value: "Alle", comment: "Einstellungen: Filter alle"), desc: NSLocalizedString("settings_filter_all_desc", value: "Alles zeigen", comment: "Einstellungen: Filter alle Beschreibung"), value: "alle", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_open_title", value: "Nur offene", comment: "Einstellungen: Filter offene"), desc: NSLocalizedString("settings_filter_open_desc", value: "Ohne erledigte", comment: "Einstellungen: Filter offene Beschreibung"), value: "offen", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_overdue_title", value: "Nur überfällige", comment: "Einstellungen: Filter überfällige"), desc: NSLocalizedString("settings_filter_overdue_desc", value: "Frist vorbei", comment: "Einstellungen: Filter überfällige Beschreibung"), value: "überfällig", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_done_title", value: "Nur erledigte", comment: "Einstellungen: Filter erledigte"), desc: NSLocalizedString("settings_filter_done_desc", value: "Fertige Aufgaben", comment: "Einstellungen: Filter erledigte Beschreibung"), value: "erledigt", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("homework_filter_trash", value: "Papierkorb", comment: "Einstellungen: Filter Papierkorb"), desc: NSLocalizedString("settings_filter_trash_desc", value: "Ausgeblendete", comment: "Einstellungen: Filter Papierkorb Beschreibung"), value: "papierkorb", selection: $vm.values.hwStatus)
                }
                Toggle(NSLocalizedString("settings_toggle_hw_tests", value: "Tests und Prüfungen einbeziehen", comment: "Einstellungen: Tests einbeziehen"), isOn: $vm.values.hwTests)
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
                Toggle(NSLocalizedString("settings_toggle_wetter_map", value: "Wetterkarte anzeigen", comment: "Einstellungen: Wetterkarte"), isOn: $vm.values.ovWetter)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))
                TextField(NSLocalizedString("settings_wetter_city_placeholder", value: "Wetter: Stadt (optional)", comment: "Einstellungen: Wetterstadt Platzhalter"), text: $vm.values.wetterCity)
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
                (store.isDemo ? Text("Demo-Modus") : Text("Server"))
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                if store.isDemo {
                    Text("Es werden ausschließlich synthetische Beispieldaten vom lokalen Demo-Server geladen.")
                        .font(UberFont.text(13))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                } else {
                    TextField(NSLocalizedString("settings_baseurl_placeholder", value: "Basis-URL", comment: "Einstellungen: Basis-URL Platzhalter"), text: $vm.baseURL)
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
                Toggle(NSLocalizedString("settings_toggle_dev_options", value: "Entwickleroptionen aktivieren", comment: "Einstellungen: Entwickleroptionen"), isOn: $developerOptionsEnabled)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))

                if developerOptionsEnabled {
                    Toggle(NSLocalizedString("settings_toggle_onboarding_restart", value: "Onboarding erneut durchlaufen", comment: "Einstellungen: Onboarding erneut"), isOn: onboardingRestartBinding)
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
