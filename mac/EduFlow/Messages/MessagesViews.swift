import SwiftUI

/// Nachrichten als einspaltige Liste (kompakt, 400px): Suche plus
/// Typfilter oben, darunter die Liste. Antippen öffnet den Thread
/// als eigene Ansicht mit Zurück-Button.
public struct MessagesView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @State private var vm: MessagesViewModel
    /// Nur die Eingabe; das Suchfeld selbst ist von uns gezeichnet
    /// (`UberSearchField`, kein `NSSearchField`).
    @State private var searchText = ""
    /// Absender-Auswahl aufgeklappt.
    @State private var senderMenuOpen = false
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
                "Messages",
                stats: vm.visibleItems.isEmpty ? nil : messageStats
            )
            searchbar
            if let marked = vm.markedMessage {
                Notice(marked)
            }
            if let error = vm.error, vm.visibleItems.isEmpty {
                ErrorView(message: error.message) {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                }
            } else {
                listPane
            }
        }
        .padding(20)
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("messages_nav_list", value: "Messages", comment: "Nachrichten: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        // Live-Suche: erst ab drei Buchstaben, dann entprellt nach 300 ms
        // nachladen (Tippen soll nicht bei jedem Zeichen einen Request auslösen).
        .onChange(of: searchText) { _, newValue in
            Task { await vm.searchLive(newValue, onSessionExpired: onSessionExpired) }
        }
    }

    /// Kopf-Statistik: Gesamtzahl plus Ungelesene (lokal getrackt).
    private var messageStats: String {
        let total = String(format: NSLocalizedString("messages_count", value: "%d messages", comment: "Nachrichten: Anzahl"), vm.visibleItems.count)
        guard vm.unreadCount > 0 else {
            return total
        }
        return total + " · " + String(format: NSLocalizedString("messages_unread_count", value: "%d unread", comment: "Nachrichten: Anzahl ungelesen"), vm.unreadCount)
    }

    // MARK: - Suchleiste (`.searchbar`, eigenes Suchfeld + eigene Knöpfe)

    private var searchbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Selbst gezeichnetes Suchfeld: Lupe, Kreuz und Fokus-Ring
                // kommen aus `UberSearchField`, damit die Leiste in allen
                // Ansichten genau so aussieht wie im Web.
                UberSearchField(
                    text: $searchText,
                    prompt: NSLocalizedString("messages_search_placeholder", value: "Search messages and senders", comment: "Nachrichten: Suche Platzhalter")
                )
                .frame(maxWidth: 320)
                // Absender-Filter als eigene Pille, kein System-Menü.
                senderFilter
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
            }
            HStack(spacing: 8) {
                IconButton(
                    icon: "arrow.clockwise",
                    label: NSLocalizedString("messages_action_reload", value: "Reload", comment: "Nachrichten: neu laden")
                ) {
                    Task { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
                }
                IconButton(
                    icon: "envelope.open",
                    label: NSLocalizedString("messages_action_mark_read", value: "Mark all as read", comment: "Nachrichten: alle als gelesen")
                ) {
                    Task { await vm.markAllRead(onSessionExpired: onSessionExpired) }
                }
                Spacer()
                // Typfilter als eigene Pillenleiste (wie Android), damit
                // keine native Menü-Optik durchschimmert.
                typePills
                Spacer()
                IconButton(
                    icon: "plus",
                    label: NSLocalizedString("messages_nav_compose", value: "New message", comment: "Nachrichten: Verfassen-Titel"),
                    action: onCompose
                )
            }
        }
    }

    /// Absender einschränken. Eigene Pille mit eigenem Popover — bewusst
    /// kein `Menu`: dessen Label setzt die Schrift selbst und wird im Dark
    /// Mode schwarz. Die Auswahl hier nutzt dieselben Farben wie die Seite.
    private var senderFilter: some View {
        Button { senderMenuOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "person")
                    .font(.system(size: 12, weight: .semibold))
                Text(senderLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(UberFont.text(13, weight: .semibold))
            .foregroundStyle(vm.sender.isEmpty ? EduFlowPalette.inkMuted(scheme) : accent.resolvedInk(scheme))
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(vm.sender.isEmpty ? EduFlowPalette.surface2(scheme) : accent.resolved(scheme))
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(vm.sender.isEmpty ? EduFlowPalette.border(scheme) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(NSLocalizedString("messages_sender_filter", value: "Filter by sender", comment: "Nachrichten: Absenderfilter"))
        .popover(isPresented: $senderMenuOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("messages_sender_filter", value: "Filter by sender", comment: "Nachrichten: Absenderfilter"))
                    .font(UberFont.text(12, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .padding(.bottom, 2)
                senderOption("", NSLocalizedString("messages_sender_all", value: "All senders", comment: "Nachrichten: alle Absender"))
                ForEach(vm.senders, id: \.self) { sender in
                    senderOption(sender, sender)
                }
                if vm.senders.isEmpty {
                    Text(NSLocalizedString("messages_sender_none", value: "No sender loaded yet.", comment: "Nachrichten: keine Absender"))
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(EduFlowPalette.card(scheme))
        }
    }

    private var senderLabel: String {
        vm.sender.isEmpty
            ? NSLocalizedString("messages_sender_all", value: "All senders", comment: "Nachrichten: alle Absender")
            : vm.sender
    }

    private func senderOption(_ value: String, _ title: String) -> some View {
        let selected = vm.sender == value
        return Button {
            vm.sender = value
            senderMenuOpen = false
            Task { await vm.load(onSessionExpired: onSessionExpired) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "person")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 14)
                Text(title)
                    .font(UberFont.text(13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? accent.resolvedInk(scheme) : EduFlowPalette.ink(scheme))
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.resolved(scheme) : Color.clear)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var typePills: some View {
        HStack(spacing: 4) {
            ForEach(MessageTypes.all, id: \.self) { type in
                let selected = vm.type == type
                Button {
                    vm.type = type
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                } label: {
                    Text(MessageTypes.label(type))
                        .font(UberFont.text(12, weight: .semibold))
                        // Auf der ausgewählten Pille die zur Akzentfarbe
                        // passende Schrift (bei schwarzem Akzent im Dark Mode
                        // dunkel auf hellem Grund), sonst die gedämpfte Tinte.
                        .foregroundStyle(selected ? accent.resolvedInk(scheme) : EduFlowPalette.inkMuted(scheme))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(selected ? accent.resolved(scheme) : Color.clear)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MessageTypes.label(type))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(EduFlowPalette.surface2(scheme))
        .overlay {
            Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
        .clipShape(.capsule)
    }

    // MARK: - Liste (`.mail-list-pane`)

    private var listPane: some View {
        ScrollView {
            ScrollOffsetSentinel()
            LazyVStack(spacing: 8) {
                // Offline-Hinweis über der Liste: die Nachrichten selbst
                // bleiben sichtbar, nur ihre Herkunft wird benannt.
                if vm.cachedAt != nil {
                    OfflineNotice(savedAt: vm.cachedAt)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                }
                if vm.isLoading && vm.visibleItems.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.visibleItems.isEmpty {
                    Text(NSLocalizedString("messages_empty", value: "No messages.", comment: "Nachrichten: leer"))
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    ForEach(Array(vm.visibleItems.enumerated()), id: \.element.id) { index, message in
                        MessageRow(
                            message: message,
                            unread: vm.isUnread(message),
                            selected: false
                        ) {
                            vm.markSeen(message.id)
                            onThread(message.header)
                        }
                        .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        PillButton(vm.isLoadingMore ? NSLocalizedString("common_loading", value: "Loading …", comment: "Laden läuft") : String(format: NSLocalizedString("messages_load_more", value: "Load more (%d/%d)", comment: "Nachrichten: mehr laden"), vm.visibleItems.count, vm.total), style: .smallLight) {
                            Task { await vm.loadMore(onSessionExpired: onSessionExpired) }
                        }
                        .disabled(vm.isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(2)
        }
        .refreshable {
            await vm.load(refresh: true, onSessionExpired: onSessionExpired)
        }
    }
}

/// Icon-Aktionen nutzen die gemeinsame Schnittstelle aus Paket 1
/// (`IconButton` in `Views/CommonViews.swift`: Kreis-Hover, Fokus-Ring,
/// VoiceOver-Name, Tooltip) — keine eigene Button-API.

/// Nachrichten-Zeile (`.msg-row`): Absender plus Datum, Betreff (fett,
/// einzeilig), Vorschau (grau, zweizeilig, nur bei Resttext), Tags und
/// Gelesen-Status (Punkt plus „Neu“-Tag bei ungelesen).
/// Ausgewählt mit Tinten-Rahmen auf Fläche 1.
private struct MessageRow: View {
    @Environment(\.colorScheme) var scheme
    @State private var hovering = false
    let message: MessageDTO
    let unread: Bool
    let selected: Bool
    let action: () -> Void

    private var author: String {
        let name = message.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return NSLocalizedString("common_unknown_author", value: "(unknown)", comment: "Nachrichten: unbekannter Absender")
        }
        return message.author
    }

    private var timestamp: String {
        if !message.timestamp.isEmpty {
            return message.timestamp
        }
        return message.timestampIso
    }

    private var subject: String {
        MessagePreview.subject(for: message)
    }

    private var preview: String {
        MessagePreview.preview(for: message)
    }

    /// Typ-Tag unterdrücken, wenn er den Betreff nur wiederholt.
    private var showsTypeTag: Bool {
        let label = message.typeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return false
        }
        return label.caseInsensitiveCompare(subject.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
    }

    private var accessibilityText: String {
        var parts = [subject, author]
        if !timestamp.isEmpty {
            parts.append(timestamp)
        }
        if !preview.isEmpty {
            parts.append(preview)
        }
        parts.append(unread
            ? NSLocalizedString("messages_state_unread", value: "Unread", comment: "Nachrichten: Status ungelesen")
            : NSLocalizedString("messages_state_read", value: "Read", comment: "Nachrichten: Status gelesen"))
        return parts.joined(separator: ", ")
    }

    /// Vollständiger Text als Fließtext (mehrere Zeilen zu einer Zeile
    /// zusammengezogen) — das ist der Text, der links groß steht.
    private var messageText: String {
        let flat = message.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if flat.isEmpty {
            return subject
        }
        return flat
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(unread ? EduFlowPalette.blue : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                    .accessibilityHidden(true)
                // Links: die eigentliche Nachricht, groß und gut lesbar.
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: messageText)
                        .font(UberFont.text(15, weight: .medium))
                        .lineSpacing(3)
                        .foregroundStyle(EduFlowPalette.ink(scheme))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if unread || showsTypeTag || message.reactionCount > 0 || !message.attachments.isEmpty {
                        HStack(spacing: 6) {
                            if unread {
                                Tag(NSLocalizedString("messages_unread", value: "New", comment: "Nachrichten: Ungelesen-Tag"), style: .solid)
                            }
                            if showsTypeTag {
                                Tag(message.typeLabel, style: .muted)
                            }
                            if message.reactionCount > 0 {
                                Text(verbatim: "♥ \(message.reactionCount)")
                                    .font(UberFont.text(12, weight: .semibold))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                            if !message.attachments.isEmpty {
                                Text(verbatim: "📎 \(message.attachments.count)")
                                    .font(UberFont.text(12, weight: .semibold))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                        }
                    }
                }
                // Rechts: Titel, Absender und Datum, alles rechtsbündig.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: subject)
                        .font(UberFont.text(14, weight: .heavy))
                        .tracking(-0.2)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    Text(verbatim: author)
                        .font(UberFont.text(13, weight: .semibold))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .lineLimit(1)
                    if !timestamp.isEmpty {
                        Text(verbatim: timestamp)
                            .font(UberFont.text(12))
                            .foregroundStyle(EduFlowPalette.inkDim(scheme))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 150, idealWidth: 210, maxWidth: 260, alignment: .trailing)
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
        .accessibilityLabel(Text(verbatim: accessibilityText))
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

    /// Leerer Autor → lokalisiert „(unbekannt)“, nie hartcodiert.
    static func authorName(_ author: String) -> String {
        if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString("common_unknown_author", value: "(unknown)", comment: "Nachrichten: unbekannter Absender")
        }
        return author
    }

    /// Leerer Dateiname → nummerierter Fallback, nie leer anzeigen.
    static func attachmentName(_ name: String, index: Int) -> String {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(format: NSLocalizedString("messages_file_fallback", value: "File %d", comment: "Nachrichten: Dateiname-Fallback"), index + 1)
        }
        return name
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
                    Text("Cached")
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
                        Text(verbatim: ThreadDetail.authorName(message.author))
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
                Text("Files")
                    .font(UberFont.text(14, weight: .heavy))
                VStack(spacing: 8) {
                    ForEach(message.attachmentNames.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text(verbatim: ThreadDetail.attachmentName(message.attachmentNames[index], index: index))
                                .font(UberFont.text(14, weight: .semibold))
                            Spacer()
                            if vm.downloadingIndex == index {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(NSLocalizedString("Load", value: "Load", comment: "UI-Literal")) {
                                    Task {
                                        await vm.download(
                                            eventId: message.id,
                                            index: index,
                                            filename: ThreadDetail.attachmentName(message.attachmentNames[index], index: index),
                                            onSessionExpired: onSessionExpired
                                        )
                                    }
                                }
                                .buttonStyle(UberButtonStyle(.smallLight))
                                .hoverLift()
                                .accessibilityLabel(Text(NSLocalizedString("messages_attachment_load", value: "Load attachment", comment: "Nachrichten: Anhang laden") + ": " + ThreadDetail.attachmentName(message.attachmentNames[index], index: index)))
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
                    ShareLink(NSLocalizedString("Share downloaded file", value: "Share downloaded file", comment: "UI-Literal"), item: file)
                        .font(UberFont.text(14, weight: .semibold))
                }
            }
            if !vm.thread.replies.isEmpty {
                Text(String(format: NSLocalizedString("messages_replies_count", value: "Replies (%d)", comment: "Nachrichten: Antwortanzahl"), vm.thread.summary.replies))
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
            Text("Write a reply")
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
            PillButton(vm.isReplying ? "Sending …" : "Replies") {
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
                Text("No likes.")
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
                Button(NSLocalizedString("‹ Back", value: "‹ Back", comment: "UI-Literal")) { onBack() }
                    .font(UberFont.text(13, weight: .bold))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .buttonStyle(.plain)
                // Offline-Hinweis, wenn der Thread aus dem lokalen Cache
                // kommt (Likes und Antworten bleiben lesbar).
                if vm.threadCachedAt != nil {
                    OfflineNotice(savedAt: vm.threadCachedAt)
                }
                ThreadDetail(message: message, vm: vm, onSessionExpired: onSessionExpired)
            }
            .padding(20)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("messages_nav_thread", value: "Thread", comment: "Nachrichten: Thread-Titel"))
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
                PageHead("New message")
                UberCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: NSLocalizedString("messages_recipients_chosen", value: "Recipients (%d selected)", comment: "Nachrichten: Empfängerzahl"), vm.selected.count))
                            .font(UberFont.text(12, weight: .bold))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        UberSearchField(
                            text: $vm.search,
                            prompt: NSLocalizedString("Search", value: "Search", comment: "Nachrichten: Empfängersuche Platzhalter")
                        )
                        if vm.recipientsCachedAt != nil {
                            OfflineNotice(savedAt: vm.recipientsCachedAt)
                        }
                        if vm.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(vm.filtered, id: \.id) { recipient in
                                UberCheckRow(isOn: vm.selected.contains(recipient.id)) {
                                    HStack {
                                        Text(recipient.name)
                                            .font(UberFont.text(14, weight: .medium))
                                        Spacer()
                                        Text(recipient.kind)
                                            .font(UberFont.text(12))
                                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    }
                                } action: {
                                    vm.toggle(recipient.id)
                                }
                            }
                            if vm.canLoadMoreRecipients {
                                PillButton(vm.isLoadingMoreRecipients ? NSLocalizedString("common_loading", value: "Loading …", comment: "Laden läuft") : String(format: NSLocalizedString("messages_load_more", value: "Load more (%d/%d)", comment: "Nachrichten: mehr laden"), vm.recipients.count, vm.recipientTotal), style: .smallLight) {
                                    Task { await vm.loadMoreRecipients(onSessionExpired: onSessionExpired) }
                                }
                                .disabled(vm.isLoadingMoreRecipients)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
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
                PillButton(vm.isSending ? "Sending …" : "Send") {
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
        .navigationTitle(NSLocalizedString("New message", value: "New message", comment: "Nachrichten: Verfassen-Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }
}
