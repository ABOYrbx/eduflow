import SwiftUI

// MARK: - Thread (Paket C, Redesign-PNG)
//
// Nachricht + Likes/Antworten + Antwort schreiben (geht an alle im
// Thread, wie Web). Anhänge per Kurzzeit-Token (`?dl=`).

struct ThreadView: View {
    @EnvironmentObject var store: TokenStore
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: ThreadViewModel
    @State private var downloadError: String?
    let service: MessagesService
    let message: MessageItem

    init(service: MessagesService, message: MessageItem) {
        self.service = service
        self.message = message
        _viewModel = StateObject(wrappedValue: ThreadViewModel(
            service: service, messageID: message.uid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MessageCard(message: message)

                if let atts = message.attachments, !atts.isEmpty {
                    SectionLabel(text: "Dateien (\(atts.count))")
                    ForEach(atts.indices, id: \.self) { i in
                        Button {
                            Task { await downloadAttachment(index: i) }
                        } label: {
                            HStack {
                                Image(systemName: "paperclip")
                                Text(atts[i].name?.isEmpty == false ? atts[i].name! : "Datei \(i + 1)")
                                    .font(.callout)
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                            }
                            .foregroundStyle(Color.rInk)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.rCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.rCardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = viewModel.error {
                    AuthAwareError(error: error, onReLogin: { Task { await reLogin() } },
                                   onDismiss: { viewModel.error = nil })
                }
                if let err = downloadError {
                    ErrorBox(message: err)
                }

                if viewModel.isLoading && viewModel.thread == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(32)
                } else if let thread = viewModel.thread {
                    if thread.cached {
                        Text("Aus Cache geladen.")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                    }
                    if !thread.likes.isEmpty {
                        SectionLabel(text: "Likes (\(thread.summary?.likes ?? thread.likes.count))")
                        ForEach(thread.likes.indices, id: \.self) { i in
                            Text("♥ \(thread.likes[i].name ?? "–")"
                                + ((thread.likes[i].date).map { " · \($0)" } ?? ""))
                                .font(.callout)
                                .foregroundStyle(Color.rInk)
                        }
                    }
                    SectionLabel(text: 
                        "Antworten (\(thread.summary?.replies ?? thread.replies.count))")
                    if thread.replies.isEmpty {
                        EmptyBox(message: "Noch keine Antworten.")
                    } else {
                        ForEach(thread.replies.indices, id: \.self) { i in
                            EduCard {
                                HStack(alignment: .top, spacing: 10) {
                                    AvatarDot(initials: initials(of: thread.replies[i].name))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(thread.replies[i].name ?? "–")
                                            .font(RFont.cardTitle)
                                            .foregroundStyle(Color.rInk)
                                        if let date = thread.replies[i].date, !date.isEmpty {
                                            Text(date)
                                                .font(.caption)
                                                .foregroundStyle(Color.rMuted)
                                        }
                                        Text(thread.replies[i].text ?? "")
                                            .font(.callout)
                                            .foregroundStyle(Color.rInk)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Antworten …", text: $viewModel.replyBody, axis: .vertical)
                        .padding(12)
                        .background(Color.rCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rCardBorder, lineWidth: 1))
                    PrimaryButton(
                        text: viewModel.isSending ? "Wird gesendet …" : "Antworten",
                        action: { Task { await viewModel.sendReply() } },
                        disabled: viewModel.isSending
                            || viewModel.replyBody.trimmingCharacters(
                                in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding(16)
        }
        .background(Color.rBackground)
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }

    private func initials(of name: String?) -> String {
        let words = (name ?? "").split(separator: " ")
        return String(words.prefix(2).compactMap { $0.first }.map(String.init).joined())
    }

    /// Anhang per Kurzzeit-Token (`?dl=`) laden und öffnen.
    private func downloadAttachment(index: Int) async {
        downloadError = nil
        do {
            let url = try await service.attachmentDownloadURL(
                messageID: message.uid, index: index)
            openURL(url)
        } catch let e as APIError {
            downloadError = "\(e.message) (\(e.code))"
        } catch {
            downloadError = APIError.message(for: "UPSTREAM")
        }
    }

    private func reLogin() async {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        let client = APIClient(baseURL: base, tokenProvider: { store.currentToken() })
        await AuthService(client: { client }, store: store).logout()
    }
}

// MARK: - Verfassen (Paket C, Redesign-PNG)

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ComposeViewModel
    @State private var filter = ""
    /// Wird nach erfolgreichem Senden aufgerufen (Liste lädt neu),
    /// bevor die Ansicht geschlossen wird.
    let onSent: () async -> Void

    private static let bodyMax = 5000

    init(service: MessagesService, onSent: @escaping () async -> Void = {}) {
        _viewModel = StateObject(wrappedValue: ComposeViewModel(service: service))
        self.onSent = onSent
    }

    private var visible: [RecipientItem] {
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.recipients
        }
        return viewModel.recipients.filter {
            $0.name.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHead(title: "Neue Nachricht",
                           subtitle: "Lehrer und Mitschüler wählen")
                SearchPill(placeholder: "Empfänger suchen", text: $filter)
                SectionLabel(text: "\(viewModel.selectedIDs.count) Empfänger gewählt")

                if viewModel.isLoadingRecipients {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(16)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(visible) { recipient in
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedIDs.contains(recipient.id) },
                                set: { _ in viewModel.toggleRecipient(recipient.id) }
                            )) {
                                HStack(spacing: 10) {
                                    AvatarDot(initials: initials(of: recipient.name))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(recipient.name)
                                            .font(.callout)
                                            .foregroundStyle(Color.rInk)
                                        Text(recipient.kind)
                                            .font(.caption)
                                            .foregroundStyle(Color.rMuted)
                                    }
                                }
                            }
                            .tint(Color.rPrimary)
                        }
                    }
                }

                TextField("Nachrichtentext", text: Binding(
                    get: { viewModel.body },
                    set: { viewModel.body = String($0.prefix(Self.bodyMax)) }
                ), axis: .vertical)
                .padding(12)
                .background(Color.rCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.rCardBorder, lineWidth: 1))
                Text("\(viewModel.body.count)/\(Self.bodyMax)")
                    .font(.caption)
                    .foregroundStyle(Color.rMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let error = viewModel.error {
                    ErrorBox(message: "\(error.message) (\(error.code))")
                }
                PrimaryButton(
                    text: viewModel.isSending ? "Wird gesendet …" : "Senden",
                    action: { Task { await viewModel.send() } },
                    disabled: viewModel.isSending
                )
            }
            .padding(16)
        }
        .background(Color.rBackground)
        .navigationTitle("Neue Nachricht")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadRecipients() }
        .onChange(of: viewModel.sentID) { _, sent in
            if sent != nil {
                Task {
                    await onSent()
                    dismiss()
                }
            }
        }
    }

    private func initials(of name: String) -> String {
        let words = name.split(separator: " ")
        return String(words.prefix(2).compactMap { $0.first }.map(String.init).joined())
    }
}
