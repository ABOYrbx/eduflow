import SwiftUI
import UIKit

// MARK: - Onboarding/Login (Paket A, Screen 06 aus dem Redesign-PNG)
//
// „1 VON 2 · SCHULE VERBINDEN" → „Willkommen bei EduFlow" → Felder
// (Subdomain/Benutzer/Passwort) → „Angemeldet bleiben" →
// „Sicher verbinden" → Hinweis-Karte → 2FA-Fußnote → Server-URL.
// Logik (Validierung, Fehlercodes, 2FA-Navi) unverändert gegen Paket 0.
// POST auth/login ({username, password, subdomain?, device?}) →
// ok (token, …) oder 2fa_required (pending_token, message).
// Validierung clientseitig (Benutzername/Passwort Pflicht).

struct LoginView: View {
    @EnvironmentObject var store: TokenStore
    @State private var subdomain = ""
    @State private var username = ""
    @State private var password = ""
    // Mobil sind Sitzungen immer persistent (30-Tage-Token in UserDefaults,
    // anders als das Web-Session-Cookie) — der Toggle ist PNG-Parität,
    // Standard an, und ändert den API-Aufruf nicht.
    @State private var rememberMe = true
    @State private var baseURL = ""
    @State private var showBaseURL = false
    @State private var isLoading = false
    @State private var error: APIError?
    @State private var pendingToken: String?
    @State private var showTwoFA = false
    @State private var pendingMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "1 von 2 · Schule verbinden")
                    Text("Willkommen bei EduFlow")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.rInk)
                    Text("Verbinde dein Schulkonto, damit Stundenplan, Aufgaben und Nachrichten synchronisiert werden.")
                        .font(RFont.subtitle)
                        .foregroundStyle(Color.rMuted)

                    LoginField(label: "Schul-Subdomain", placeholder: "z. B. gymnasium", text: $subdomain)
                    LoginField(label: "Benutzername", placeholder: "Dein Schul-Login", text: $username)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passwort")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.rInk)
                        SecureField("••••••••", text: $password)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.rCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.rCardBorder, lineWidth: 1))
                    }

                    Toggle("Angemeldet bleiben", isOn: $rememberMe)

                    if let error {
                        ErrorBox(message: "\(error.message) (\(error.code))")
                    }
                    if isLoading {
                        LoadingBox()
                    }
                    PrimaryButton(
                        text: isLoading ? "Verbinden …" : "Sicher verbinden",
                        action: { Task { await login() } },
                        disabled: isLoading
                    )

                    EduCard {
                        Text("Zugangsdaten bleiben lokal verschlüsselt.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text("Bei 2FA folgt ein Bestätigungscode.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rMuted)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if !showBaseURL {
                        Button("Server ändern") { showBaseURL = true }
                            .font(.callout)
                    } else {
                        LoginField(label: "Server (…/api/v1/)", placeholder: store.baseURL, text: $baseURL)
                        Text("Simulator: http://127.0.0.1:8000/api/v1/ — kein 10.0.2.2 nötig.")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                        PrimaryButton(
                            text: "Übernehmen",
                            action: {
                                store.setBaseURL(baseURL.isEmpty ? TokenStore.defaultBaseURL : baseURL)
                                showBaseURL = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color.rBackground)
            .navigationTitle("EduFlow")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { baseURL = store.baseURL }
            .navigationDestination(isPresented: $showTwoFA) {
                TwoFAView(pendingToken: pendingToken ?? "", message: pendingMessage)
                    .environmentObject(store)
            }
        }
    }

    private func client() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    private func login() async {
        isLoading = true
        self.error = nil
        do {
            let service = AuthService(client: { client() }, store: store)
            let device = UIDevice.current.model
            let result = try await service.login(
                username: username, password: password,
                subdomain: subdomain, device: device)
            if case .twoFaRequired(let pending, let message) = result {
                pendingMessage = message
                pendingToken = pending
                showTwoFA = true
            }
            // Bei .loggedIn schaltet RootView automatisch um (TokenStore).
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }
}

/// Beschriftetes Pillen-Feld im PNG-Stil (Label + Capsule-TextField).
private struct LoginField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.rInk)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.rCard)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.rCardBorder, lineWidth: 1))
        }
    }
}

struct TwoFAView: View {
    @EnvironmentObject var store: TokenStore
    let pendingToken: String
    let message: String
    @State private var code = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "2 von 2 · Code bestätigen")
                Text("Code bestätigen")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.rInk)
                if !message.isEmpty {
                    Text(message)
                        .font(RFont.subtitle)
                        .foregroundStyle(Color.rMuted)
                } else {
                    Text("Gib den Zwei-Faktor-Code aus E-Mail oder App ein.")
                        .font(RFont.subtitle)
                        .foregroundStyle(Color.rMuted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code aus E-Mail oder App")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.rInk)
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.rCard)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.rCardBorder, lineWidth: 1))
                }
                if let error {
                    ErrorBox(message: "\(error.message) (\(error.code))")
                }
                if isLoading {
                    LoadingBox()
                }
                PrimaryButton(
                    text: isLoading ? "Prüfen …" : "Bestätigen",
                    action: { Task { await submit() } },
                    disabled: isLoading || code.trimmingCharacters(in: .whitespaces).isEmpty
                )
                Text("Der Code ist 10 Minuten gültig.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.rBackground)
        .navigationTitle("Zwei-Faktor-Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        isLoading = true
        self.error = nil
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        let client = APIClient(baseURL: base, tokenProvider: { store.currentToken() })
        do {
            _ = try await AuthService(client: { client }, store: store)
                .submit2FA(pendingToken: pendingToken, code: code)
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }
}
