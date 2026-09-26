import SwiftUI

// MARK: - Geräte (Paket F, Redesign-PNG Screen 05: „Verbundene Geräte")
//
// Eigene Tokens (ohne Secrets) + gezieltes Widerrufen (Button statt
// Wisch-Geste, sofort sichtbar). 401 → Login (Abmelden).

struct DevicesView: View {
    @EnvironmentObject var store: TokenStore
    let client: APIClient
    @State private var devices: [DeviceDTO] = []
    @State private var isLoading = false
    @State private var error: APIError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHead(title: "Geräte",
                           subtitle: "Angemeldete Geräte verwalten")
                if let error {
                    AuthAwareError(error: error,
                                   onReLogin: { Task { await logout() } },
                                   onDismiss: { self.error = nil })
                }
                if isLoading && devices.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(32)
                } else if devices.isEmpty {
                    EmptyBox(message: "Keine weiteren Geräte angemeldet.")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(devices, id: \.id) { device in
                            EduCard {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text((device.device.nilIfEmpty ?? "Unbenanntes Gerät")
                                            + " (\(device.short))")
                                            .font(RFont.cardTitle)
                                            .foregroundStyle(Color.rInk)
                                        Text("Erstellt: \(device.created)")
                                            .font(RFont.cardSub)
                                            .foregroundStyle(Color.rMuted)
                                        Text("Läuft ab: \(device.expires)")
                                            .font(RFont.cardSub)
                                            .foregroundStyle(Color.rMuted)
                                    }
                                    .layoutPriority(1)
                                    Spacer()
                                    Button("Entfernen") {
                                        Task { await revoke(device) }
                                    }
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.rBackground)
        .navigationTitle("Geräte")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            devices = try await AuthService(client: { client }, store: store).devices().items
            self.error = nil
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    private func revoke(_ device: DeviceDTO) async {
        do {
            try await AuthService(client: { client }, store: store).revokeDevice(id: device.id)
            devices.removeAll { $0.id == device.id }
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
    }

    private func logout() async {
        await AuthService(client: { client }, store: store).logout()
    }
}
