import SwiftUI

// MARK: - Hausaufgaben-Liste (Paket B, Redesign-PNG Screen 01)
//
// Header, Titel + Untertitel, Suche, Chips Alle/Offen/Überfällig/Erledigt,
// Zähler-Zeile („4 OFFEN · 1 ÜBERFÄLLIG"), Karten: Status-Dot links, Titel
// + „Fällig · Lehrkraft"-Sub, rechts Status-Pill + Kreis (Tap =
// erledigt/wieder öffnen). Papierkorb über den Button neben dem Zähler
// (Zurückholen markiert gleichzeitig als offen, wie im Web).
// Wisch-Geste zur Seite legt in den Papierkorb / holt zurück.

/// Chips aus dem PNG (Screen 01); Papierkorb läuft über den Button darunter.
private let homeworkChips: [(label: String, status: String)] = [
    ("Alle", HomeworkStatusFilter.alle),
    ("Offen", HomeworkStatusFilter.offen),
    ("Überfällig", HomeworkStatusFilter.ueberfaellig),
    ("Erledigt", HomeworkStatusFilter.erledigt),
]

struct HomeworkView: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var viewModel: HomeworkViewModel

    init(service: HomeworkService) {
        _viewModel = StateObject(wrappedValue: HomeworkViewModel(service: service))
    }

    private func client() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    private var inTrash: Bool { viewModel.status == HomeworkStatusFilter.papierkorb }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                AppHeader(client: client())
                ScreenHead(title: "Hausaufgaben",
                           subtitle: "Deine Aufgaben im Überblick")
                SearchPill(placeholder: "Titel, Fach oder Lehrkraft",
                           text: Binding(
                            get: { viewModel.query },
                            set: { viewModel.onQuery($0) }
                           ))
                FilterChips(
                    options: homeworkChips.map(\.label),
                    selected: Binding(
                        get: { homeworkChips.first(where: { $0.status == viewModel.status })?.label ?? "" },
                        set: { label in
                            if let chip = homeworkChips.first(where: { $0.label == label }) {
                                Task { await viewModel.onStatus(chip.status) }
                            }
                        }
                    ))
                Toggle("Tests/Prüfungen einbeziehen", isOn: Binding(
                    get: { viewModel.includeTests },
                    set: { value in
                        _ = Task { await viewModel.onIncludeTests(value) }
                    }
                ))
                .font(.footnote)
                .foregroundStyle(Color.rMuted)

                HStack {
                    SectionLabel(text: inTrash
                        ? "Papierkorb · \(viewModel.total) Einträge"
                        : "\(viewModel.counts.offen) offen · \(viewModel.counts.ueberfaellig) überfällig")
                    Spacer()
                    Button(inTrash ? "Zurück"
                           : "Papierkorb (\(viewModel.counts.papierkorb))") {
                        Task {
                            await viewModel.onStatus(inTrash
                                ? HomeworkStatusFilter.alle
                                : HomeworkStatusFilter.papierkorb)
                        }
                    }
                    .font(.caption)
                    Button("Aktualisieren") {
                        Task { await viewModel.refresh() }
                    }
                    .font(.caption)
                    .disabled(viewModel.isLoading)
                }
                if !viewModel.cacheInfo.isEmpty {
                    Text(viewModel.cacheInfo)
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
                } else if viewModel.items.isEmpty {
                    VStack(spacing: 8) {
                        EmptyBox(message: inTrash
                            ? "Der Papierkorb ist leer."
                            : "Keine Hausaufgaben gefunden.")
                        Button("Neu laden") { Task { await viewModel.refresh() } }
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    List {
                        ForEach(viewModel.items, id: \.uid) { item in
                            HomeworkCard(
                                item: item,
                                pending: viewModel.pendingIDs.contains(item.uid),
                                onToggleDone: { Task { await viewModel.toggleDone(item) } }
                            )
                            // Wisch-Geste nur für den Papierkorb (erledigt
                            // geht über den Kreis): hineinlegen/zurückholen.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button(item.isHidden == true ? "Wiederherstellen" : "Papierkorb") {
                                    Task { await viewModel.toggleTrash(item) }
                                }
                                .tint(.red)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                        if viewModel.canLoadMore {
                            Button {
                                Task { await viewModel.loadMore() }
                            } label: {
                                if viewModel.isLoadingMore { ProgressView() }
                                else { Text("Mehr laden (\(viewModel.items.count)/\(viewModel.total))") }
                            }
                            .disabled(viewModel.isLoadingMore)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.rBackground)
                    .refreshable { await viewModel.refresh() }
                }
            }
            .padding(16)
            .background(Color.rBackground)
            .navigationTitle("Hausaufgaben")
            .task { await viewModel.refresh() }
        }
    }

    private func reLogin() async {
        await AuthService(client: { client() }, store: store).logout()
    }
}

// MARK: - Aufgabenkarte (PNG: Dot, Titel + Sub, Pill + Kreis rechts)

struct HomeworkCard: View {
    let item: HomeworkItem
    let pending: Bool
    let onToggleDone: () -> Void

    private var dot: Color {
        if item.isDone == true || item.status == HomeworkItemStatus.erledigt {
            return .rDotGreen
        }
        switch item.status {
        case HomeworkItemStatus.ueberfaellig: return .rDotRed
        case HomeworkItemStatus.heute: return .rDotOrange
        default: return .rDotBlue
        }
    }

    private var title: String {
        let t = (item.title?.nilIfEmpty) ?? "Hausaufgabe #\(item.uid)"
        if let subject = item.subject?.nilIfEmpty {
            return "\(subject) - \(t)"
        }
        return t
    }

    private var sub: String {
        let whenText = (item.dueDisplay?.nilIfEmpty) ?? (item.status ?? "")
        if let author = item.author?.nilIfEmpty {
            return "\(whenText) · \(author)"
        }
        return whenText
    }

    private var pillText: String {
        if item.isHidden == true { return "Papierkorb" }
        return item.status ?? "Offen"
    }

    var body: some View {
        EduCard {
            HStack(spacing: 12) {
                Circle()
                    .fill(dot)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RFont.cardTitle)
                        .foregroundStyle(Color.rInk)
                    Text(sub)
                        .font(RFont.cardSub)
                        .foregroundStyle(Color.rMuted)
                }
                .layoutPriority(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    StatusPill(text: pillText, dot: dot)
                    DoneCircle(done: item.isDone == true,
                               pending: pending,
                               action: onToggleDone)
                }
            }
        }
    }
}

/// Kreis-Checkbox: Tap schaltet erledigt/wieder öffnen (sofort sichtbar).
struct DoneCircle: View {
    let done: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if pending {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else if done {
                    Circle()
                        .fill(Color.rPrimary)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.rOnPrimary)
                } else {
                    Circle()
                        .stroke(Color.rMuted, lineWidth: 1)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(pending)
    }
}
