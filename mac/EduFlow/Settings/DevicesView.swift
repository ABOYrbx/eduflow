import SwiftUI

/// Geräte-Ansicht (Paket A): eigene Sitzungen ohne Secrets als
/// Datei-Zeilen (`.modal-file`), gezielt widerrufen.
public struct DevicesView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: DevicesViewModel
    private let onSessionExpired: () -> Void

    public init(store: TokenStore, onSessionExpired: @escaping () -> Void) {
        _vm = State(initialValue: DevicesViewModel(store: store))
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    "Geräte",
                    stats: vm.devices.isEmpty ? nil : String(format: NSLocalizedString("devices_count", value: "%d Sitzungen", comment: "Geräte: Sitzungszahl"), vm.devices.count)
                )
                if vm.isLoading && vm.devices.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if let error = vm.error, vm.devices.isEmpty {
                    ErrorView(message: error.message) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                } else if vm.devices.isEmpty {
                    Text("Keine weiteren Sitzungen.")
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(vm.devices.enumerated()), id: \.element.id) { index, device in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    (device.device.isEmpty ? Text("Unbekanntes Gerät") : Text(verbatim: device.device))
                                        .font(UberFont.text(14, weight: .bold))
                                    Text(verbatim: "\(device.short) · \(device.created)")
                                        .font(UberFont.text(12))
                                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    Text(String(format: NSLocalizedString("devices_valid_until", value: "Gültig bis %@", comment: "Geräte: Gültigkeit"), device.expires))
                                        .font(UberFont.text(12))
                                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                }
                                Spacer()
                                Button("Entfernen") {
                                    Task { await vm.revoke(device, onSessionExpired: onSessionExpired) }
                                }
                                .buttonStyle(UberButtonStyle(.smallLight))
                                .hoverLift()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(EduFlowPalette.card(scheme))
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                            }
                            .riseIn(delay: Double(min(index, 8)) * 0.06)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("settings_devices_nav", value: "Geräte", comment: "Geräte: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }
}
