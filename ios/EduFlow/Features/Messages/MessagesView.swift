import SwiftUI

// MARK: - Nachrichten-Liste (Paket C, Redesign-PNG Screen 02)
//
// Header, Titel + Untertitel, Suche, Chips Alle/Ungelesen/Mit Dateien,
// Avatar-Karten (Name + Zeit, Betreff fett, Vorschau grau, Punkt bei
// ungelesen), FAB zum Verfassen.

struct MessagesView: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var viewModel: MessagesViewModel
    let service: MessagesService

    init(service: MessagesService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: MessagesViewModel(service: service))
    }

    private func client() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    AppHeader(client: client())
                    ScreenHead(title: "Nachrichten",
                               subtitle: "Mitteilungen aus deiner Schule")
                    SearchPill(placeholder: "Nachrichten durchsuchen",
                               text: Binding(
                                   get: { viewModel.query },
                                   set: { viewModel.onQuery($0) }
                               ))
                    FilterChips(options: MsgFilter.allCases.map(\.rawValue),
                                selected: Binding(
                                    get: { viewModel.filter.rawValue },
                                    set: { raw in
                                        if let f = MsgFilter(rawValue: raw) {
                                            viewModel.onFilter(f)
                                        }
                                    }
                                ))
                    HStack {
                        SectionLabel(text: "\(viewModel.visibleItems.count) von \(viewModel.total) Nachrichten")
                        Spacer()
                        Button("Alle gelesen") {
                            Task { await viewModel.markRead() }
                        }
                        .font(.caption)
                    }
                    if viewModel.marked > 0 {
                        Text("\(viewModel.marked) als gelesen markiert.")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                    }

                    if let error = viewModel.error {
                        AuthAwareError(error: error, onReLogin: { Task { await reLogin() } },
                                       onDismiss: { viewModel.error = nil })
                    }

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(32)
                    } else if viewModel.visibleItems.isEmpty {
                        VStack(spacing: 8) {
                            EmptyBox(message: {
                                switch viewModel.filter {
                                case .ungelesen: return "Alles gelesen. Sehr gut."
                                case .mitDateien: return "Keine Nachrichten mit Dateien."
                                case .alle: return "Keine Nachrichten gefunden."
                                }
                            }())
                            Button("Neu laden") { Task { await viewModel.refresh() } }
                                .font(.callout)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.visibleItems, id: \.uid) { msg in
                                    NavigationLink {
                                        ThreadView(service: service, message: msg)
                                    } label: {
                                        MessageCard(
                                            message: msg,
                                            unread: !viewModel.seenIDs.contains(msg.uid)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        viewModel.openThread(msg.uid)
                                    })
                                }
                                if viewModel.canLoadMore {
                                    Button {
                                        Task { await viewModel.loadMore() }
                                    } label: {
                                        if viewModel.isLoadingMore { ProgressView() }
                                        else {
                                            Text("Mehr laden (\(viewModel.items.count)/\(viewModel.total))")
                                        }
                                    }
                                    .disabled(viewModel.isLoadingMore)
                                }
                                Spacer().frame(height: 88)
                            }
                        }
                        .refreshable { await viewModel.refresh() }
                    }
                }
                .padding(16)

                NavigationLink {
                    ComposeView(service: service) {
                        await viewModel.refresh()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.rPrimary)
                            .frame(width: 56, height: 56)
                        Image(systemName: "plus")
                            .foregroundStyle(Color.rOnPrimary)
                            .font(.title2.bold())
                    }
                }
                .padding(16)
            }
            .background(Color.rBackground)
            .task { await viewModel.refresh() }
            .onAppear { viewModel.syncSeen() }
        }
    }

    private func reLogin() async {
        await AuthService(client: { client() }, store: store).logout()
    }
}

struct MessageCard: View {
    let message: MessageItem
    var unread = false

    var body: some View {
        EduCard {
            HStack(alignment: .top, spacing: 12) {
                AvatarDot(initials: message.initials.isEmpty ? "–" : message.initials)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.author?.isEmpty == false ? message.author! : "–")
                            .font(RFont.cardTitle)
                            .foregroundStyle(Color.rInk)
                        Spacer()
                        Text(message.timestamp ?? message.timestampIso ?? "")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                    }
                    Text(message.bodyLine)
                        .font(RFont.cardSub)
                        .foregroundStyle(Color.rMuted)
                    if let atts = message.attachments, !atts.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(atts.indices, id: \.self) { i in
                                Text("📎 \(atts[i].name?.isEmpty == false ? atts[i].name! : "Datei \(i + 1)")")
                                    .font(.caption)
                                    .foregroundStyle(Color.rMuted)
                            }
                        }
                        .padding(.top, 4)
                    }
                    if (message.reactionCount ?? 0) > 0 {
                        Text("♥ \(message.reactionCount ?? 0)")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                            .padding(.top, 2)
                    }
                }
                if unread {
                    Circle()
                        .fill(Color.rPrimary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                }
            }
        }
    }
}
