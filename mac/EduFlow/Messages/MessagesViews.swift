import SwiftUI

/// Nachrichten als einspaltige Liste (kompakt, 400px): Suche plus
/// Typfilter oben, darunter die Liste. Antippen öffnet den Thread
/// als eigene Ansicht mit Zurück-Button.
public struct MessagesView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: MessagesViewModel
    private let onThread: (MessageHeader) -> Void
    private let onCompose: () -> Void
    private let onSessionExpired: () -> Void

    public init(
        store: TokenStore,
        onThread: @escaping (MessageHeader) -> Void,
        onCompose: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _vm = State(initialValue: MessagesViewModel(store: store))
        self.onThread = onThread
        self.onCompose = onCompose
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHead(
                "Nachrichten",
                stats: vm.total == 0 ? nil : "\(vm.total) Nachrichten"
            )
            searchbar
            if let error = vm.error, vm.items.isEmpty {
                ErrorView(message: error.message) {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                }
            } else {
                listPane
            }
        }
        .padding(20)
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Nachrichten")
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }

    // MARK: - Suchleiste (`.searchbar`, zwei Reihen)

    private var searchbar: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Suchen", text: $vm.query)
                    .font(UberFont.text(15, weight: .medium))
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                Button {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(EduFlowPalette.ink(scheme))
                        .frame(width: 38, height: 38)
                        .background(EduFlowPalette.surface1(scheme))
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                Picker("Typ", selection: $vm.type) {
                    ForEach(MessageTypes.all, id: \.self) { type in
                        Text(MessageTypes.label(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
                .onChange(of: vm.type) {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
            }
            HStack(spacing: 8) {
                Button("Neu laden") {
                    Task { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                Button("Alle als gelesen") {
                    Task { await vm.markAllRead(onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                Spacer()
                Button("Neue Nachricht", action: onCompose)
                    .buttonStyle(UberButtonStyle(.smallPrimary))
                    .hoverLift()
            }
        }
    }

    // MARK: - Liste (`.mail-list-pane`)

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.items.isEmpty {
                    Text("Keine Nachrichten.")
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, message in
                        MessageRow(
                            message: message,
                            selected: false
                        ) {
                            onThread(message.header)
                        }
                        .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        Button(vm.isLoadingMore ? "Lädt …" : "Mehr laden (\(vm.items.count)/\(vm.total))") {
                            Task { await vm.loadMore(onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                        .disabled(vm.isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(2)
        }
    }
}

/// Nachrichten-Zeile (`.msg-row`): Autor plus Zeit, Snippet, Tags.
/// Ausgewählt mit Tinten-Rahmen auf Fläche 1.
private struct MessageRow: View {
    @Environment(\.colorScheme) var scheme
    @State private var hovering = false
    let message: MessageDTO
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.author.isEmpty ? "(unbekannt)" : message.author)
                        .font(UberFont.text(14, weight: .heavy))
                        .tracking(-0.2)
                        .lineLimit(1)
                    Spacer()
                    Text(message.timestamp)
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                }
                Text(message.text)
                    .font(UberFont.text(13))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .lineLimit(2)
                if !message.typeLabel.isEmpty || message.reactionCount > 0 || !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        if !message.typeLabel.isEmpty {
                            Tag(message.typeLabel, style: .muted)
                        }
                        if message.reactionCount > 0 {
                            Text("♥ \(message.reactionCount)")
                                .font(UberFont.text(12, weight: .semibold))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        }
                        if !message.attachments.isEmpty {
                            Text("📎 \(message.attachments.count)")
                                .font(UberFont.text(12, weight: .semibold))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? EduFlowPalette.surface1(scheme)
                    : (hovering ? EduFlowPalette.cardHover(scheme) : EduFlowPalette.card(scheme))
            )
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        selected ? EduFlowPalette.ink(scheme) : EduFlowPalette.border(scheme),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Detail-Ansicht (`.mail-detail`): Kopf mit Likes-Umschalter, Meta,
/// Text, Dateien, Antworten und Antwort-Editor.
public struct ThreadDetail: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.uberAccent) var accent
    @State private var showLikes = false
    let message: MessageHeader
    @Bindable var vm: ThreadViewModel
    let onSessionExpired: () -> Void

    public init(message: MessageHeader, vm: ThreadViewModel, onSessionExpired: @escaping () -> Void) {
        self.message = message
        self.vm = vm
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("♥ \(vm.thread.summary.likes)") {
                    showLikes.toggle()
                }
                .font(UberFont.text(13, weight: .bold))
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(showLikes ? accent.resolved(scheme) : EduFlowPalette.card(scheme))
                .foregroundStyle(showLikes ? accent.resolvedInk(scheme) : EduFlowPalette.ink(scheme))
                .clipShape(.capsule)
                .overlay {
                    if !showLikes {
                        Capsule().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                if vm.thread.cached {
                    Text("Zwischengespeichert")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                }
                Spacer()
            }
            if showLikes {
                likesList
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(message.author.isEmpty ? "(unbekannt)" : message.author)
                            .font(UberFont.text(15, weight: .bold))
                        Spacer()
                        Text(message.timestamp)
                            .font(UberFont.text(13))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    Text(message.text)
                        .font(UberFont.text(15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            if !message.attachmentNames.isEmpty {
                Text("Dateien")
                    .font(UberFont.text(14, weight: .heavy))
                VStack(spacing: 8) {
                    ForEach(message.attachmentNames.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text(message.attachmentNames[index])
                                .font(UberFont.text(14, weight: .semibold))
                            Spacer()
                            if vm.downloadingIndex == index {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button("Laden") {
                                    Task {
                                        await vm.download(
                                            eventId: message.id,
                                            index: index,
                                            onSessionExpired: onSessionExpired
                                        )
                                    }
                                }
                                .buttonStyle(UberButtonStyle(.smallLight))
                                .hoverLift()
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(EduFlowPalette.card(scheme))
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                        }
                    }
                }
                if let file = vm.downloadedFile {
                    ShareLink("Geladene Datei teilen", item: file)
                        .font(UberFont.text(14, weight: .semibold))
                }
            }
            if !vm.thread.replies.isEmpty {
                Text("Antworten (\(vm.thread.summary.replies))")
                    .font(UberFont.text(14, weight: .heavy))
                VStack(spacing: 8) {
                    ForEach(vm.thread.replies.indices, id: \.self) { index in
                        let reply = vm.thread.replies[index]
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(reply.name ?? "?")
                                    .font(UberFont.text(13, weight: .bold))
                                Spacer()
                                Text(reply.date ?? "")
                                    .font(UberFont.text(12))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                            Text(reply.text ?? "")
                                .font(UberFont.text(14))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(EduFlowPalette.card(scheme))
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                        }
                    }
                }
            }
            Text("Antwort schreiben")
                .font(UberFont.text(14, weight: .heavy))
            TextEditor(text: $vm.replyText)
                .font(UberFont.text(14))
                .frame(minHeight: 60)
                .padding(8)
                .background(EduFlowPalette.card(scheme))
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                }
            PillButton(vm.isReplying ? "Sendet …" : "Antworten") {
                Task { await vm.sendReply(id: message.id, onSessionExpired: onSessionExpired) }
            }
            .disabled(vm.isReplying || vm.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error = vm.error {
                Text(error.message)
                    .font(UberFont.text(14))
                    .foregroundStyle(EduFlowPalette.red)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }

    private var likesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.thread.likes.isEmpty {
                Text("Keine Likes.")
                    .font(UberFont.text(14))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            } else {
                ForEach(vm.thread.likes.indices, id: \.self) { index in
                    HStack {
                        Text(vm.thread.likes[index].name ?? "?")
                            .font(UberFont.text(14, weight: .semibold))
                        Spacer()
                        Text(vm.thread.likes[index].date ?? "")
                            .font(UberFont.text(12))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                }
            }
        }
    }
}

/// Thread als eigene Ansicht (Route `.thread`, nutzt das Detail).
public struct ThreadView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: ThreadViewModel
    private let message: MessageHeader
    private let onBack: () -> Void
    private let onSessionExpired: () -> Void

    public init(
        store: TokenStore,
        message: MessageHeader,
        onBack: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        self.message = message
        self.onBack = onBack
        self.onSessionExpired = onSessionExpired
        _vm = State(initialValue: ThreadViewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("‹ Zurück") { onBack() }
                    .font(UberFont.text(13, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .buttonStyle(.plain)
                ThreadDetail(message: message, vm: vm, onSessionExpired: onSessionExpired)
            }
            .padding(20)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Thread")
        .task { await vm.load(id: message.id, onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(id: message.id, refresh: true, onSessionExpired: onSessionExpired) }
    }
}

/// Verfassen-Ansicht (Paket B): Empfängersuche, Mehrfachauswahl, Senden.
public struct ComposeView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: ComposeViewModel
    private let onSent: () -> Void
    private let onSessionExpired: () -> Void

    public init(
        store: TokenStore,
        onSent: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _vm = State(initialValue: ComposeViewModel(store: store))
        self.onSent = onSent
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHead("Neue Nachricht")
                UberCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Empfänger (\(vm.selected.count) gewählt)")
                            .font(UberFont.text(12, weight: .bold))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        TextField("Suche", text: $vm.search)
                            .uberInput()
                            .autocorrectionDisabled()
                        if vm.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(vm.filtered, id: \.id) { recipient in
                                Toggle(isOn: Binding(
                                    get: { vm.selected.contains(recipient.id) },
                                    set: { _ in vm.toggle(recipient.id) }
                                )) {
                                    HStack {
                                        Text(recipient.name)
                                            .font(UberFont.text(14, weight: .medium))
                                        Spacer()
                                        Text(recipient.kind)
                                            .font(UberFont.text(12))
                                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    }
                                }
                            }
                        }
                    }
                }
                UberCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text")
                            .font(UberFont.text(12, weight: .bold))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        TextEditor(text: $vm.body)
                            .font(UberFont.text(14))
                            .frame(minHeight: 120)
                    }
                }
                if let error = vm.error {
                    Notice(error.message)
                }
                PillButton(vm.isSending ? "Sendet …" : "Senden") {
                    Task {
                        if await vm.send(onSessionExpired: onSessionExpired) {
                            onSent()
                        }
                    }
                }
                .disabled(!vm.canSend)
            }
            .padding(20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Neue Nachricht")
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }
}
