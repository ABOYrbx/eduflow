import SwiftUI

// MARK: - Noten (Paket E, Redesign-PNG Screen 04)
//
// Header, Titel „Noten" + „Deine Leistungen nach Fach", Schnitt-Karte
// in Primär-Farbe (Light schwarz / Dark weiß): „GESAMTSCHNITT" + Wert
// groß + „Deine Noten im Überblick". Suche, Halbjahr-Chips (falls
// mehrere), Label „FÄCHER", Zeilen: Fach + neueste „Art · Datum"
// links, Noten-Pill rechts; Tap klappt die Fachdetails auf (alle
// Noten mit Gewichtung, Lehrer, Klasse Ø, Kommentar). Fuß „Zuletzt
// synchronisierte Einträge". Schnitt/Gruppierung wie /noten.

struct GradesView: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var viewModel: GradesViewModel
    @State private var expanded: Set<String> = []

    init(service: GradesService) {
        _viewModel = StateObject(wrappedValue: GradesViewModel(service: service))
    }

    private func client() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                AppHeader(client: client())
                ScreenHead(title: "Noten",
                           subtitle: "Deine Leistungen nach Fach")
                AverageCard(avgDisplay: GradesAverage.display(viewModel.average))
                SearchPill(placeholder: "Fach, Titel oder Lehrkraft",
                           text: Binding(
                            get: { viewModel.query },
                            set: { viewModel.query = $0 }
                           ))
                if viewModel.terms.count > 1 {
                    FilterChips(
                        options: viewModel.terms.map { "\($0.label) (\($0.count))" },
                        selected: Binding(
                            get: {
                                let t = viewModel.terms.first(where: { $0.key == viewModel.term })
                                return t.map { "\($0.label) (\($0.count))" } ?? ""
                            },
                            set: { label in
                                if let t = viewModel.terms.first(where: { "\($0.label) (\($0.count))" == label }) {
                                    viewModel.term = t.key
                                }
                            }
                        ))
                }
                HStack {
                    SectionLabel(text: "Fächer")
                    Spacer()
                    Button("Aktualisieren") { Task { await viewModel.refresh() } }
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
                } else if viewModel.groups.isEmpty {
                    VStack(spacing: 8) {
                        EmptyBox(message: "Keine Noten in diesem Zeitraum.")
                        Button("Neu laden") { Task { await viewModel.refresh() } }
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    List {
                        ForEach(viewModel.groups) { group in
                            SubjectRow(
                                group: group,
                                expanded: expanded.contains(group.subject),
                                onToggle: {
                                    if expanded.contains(group.subject) {
                                        expanded.remove(group.subject)
                                    } else {
                                        expanded.insert(group.subject)
                                    }
                                }
                            )
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
                        Text("Zuletzt synchronisierte Einträge")
                            .font(.caption)
                            .foregroundStyle(Color.rMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.rBackground)
                    .refreshable { await viewModel.refresh() }
                }
            }
            .padding(16)
            .background(Color.rBackground)
            .navigationTitle("Noten")
            .task { await viewModel.refresh() }
        }
    }

    private func reLogin() async {
        await AuthService(client: { client() }, store: store).logout()
    }
}

// MARK: - Schnitt-Karte (Primär-Farbe, Light schwarz / Dark weiß)

struct AverageCard: View {
    let avgDisplay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GESAMTSCHNITT")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.rOnPrimary.opacity(0.7))
            Text(avgDisplay)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Color.rOnPrimary)
            Text("Deine Noten im Überblick")
                .font(.system(size: 13))
                .foregroundStyle(Color.rOnPrimary.opacity(0.7))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Fach-Zeile (Fach + neueste Art · Datum, Pill rechts, Tap = Details)

struct SubjectRow: View {
    let group: SubjectGroup
    let expanded: Bool
    let onToggle: () -> Void

    private var newest: GradeItem? { group.items.first }

    private var newestSub: String {
        guard let n = newest else { return "Noch keine Note" }
        let title = n.title?.nilIfEmpty ?? "Note"
        let date = n.dateDisplay?.nilIfEmpty ?? "–"
        return "\(title) · \(date)"
    }

    var body: some View {
        EduCard {
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.subject)
                            .font(RFont.cardTitle)
                            .foregroundStyle(Color.rInk)
                        Text(newestSub)
                            .font(RFont.cardSub)
                            .foregroundStyle(Color.rMuted)
                    }
                    .layoutPriority(1)
                    Spacer()
                    StatusPill(text: newest?.gradeDisplay?.nilIfEmpty ?? "–",
                               dot: badgeColor(newest?.badge))
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ø \(GradesAverage.display(group.avg)) · \(group.items.count) \(group.items.count == 1 ? "Note" : "Noten")")
                        .font(.caption)
                        .foregroundStyle(Color.rMuted)
                    ForEach(group.items, id: \.uid) { grade in
                        GradeDetailRow(grade: grade)
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

struct GradeDetailRow: View {
    let grade: GradeItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text((grade.gradeDisplay?.nilIfEmpty ?? "–")
                + ((grade.weightDisplay?.nilIfEmpty).map { " \($0)" } ?? ""))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(badgeColor(grade.badge))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text((grade.title?.nilIfEmpty) ?? "Note")
                    .font(.subheadline.bold())
                Text("\((grade.dateDisplay?.nilIfEmpty) ?? "–")"
                    + ((grade.gradeSub?.nilIfEmpty).map { " · \($0)" } ?? "")
                    + " · Gewichtung \((grade.weightDisplay?.nilIfEmpty) ?? "×1")")
                    .font(.caption)
                    .foregroundStyle(Color.rMuted)
                let meta = [(grade.teacher?.nilIfEmpty).map { "Lehrer: \($0)" },
                            (grade.classAvgDisplay?.nilIfEmpty).map { "Klasse Ø \($0)" },
                            grade.comment?.nilIfEmpty]
                    .compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(Color.rMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.rSecondaryFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private func badgeColor(_ badge: String?) -> Color {
    switch badge {
    case "g12": return .rDotGreen
    case "g3": return .rDotBlue
    case "g4": return .rDotOrange
    case "g56": return .rDotRed
    default: return .secondary
    }
}
