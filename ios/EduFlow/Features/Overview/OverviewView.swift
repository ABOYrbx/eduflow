import SwiftUI

// MARK: - Übersicht, Startseite (Paket G, PNG-Stil wie Pakete A–F)
//
// Header, „Home"-Titel + Datum, Uhr-Karte, Jetzt-Karte in
// Primär-Farbe (Jetzt / Als Nächstes), Wetterkarte (nur wenn
// `ov_wetter` an), neueste Nachrichten (`ov_unread`-Limit), offene
// Hausaufgaben (`ov_homework`-Limit). Inhalte wie `/` (Web-Übersicht, Logik im
// ViewModel — hier nur Anzeige); 401 → Login (Abmelden).

struct OverviewView: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var viewModel: OverviewViewModel
    @State private var now = Date()

    init(client: APIClient) {
        _viewModel = StateObject(wrappedValue: OverviewViewModel(
            client: { client },
            settingsService: SettingsService(client: { client }),
            timetableService: TimetableService(client: { client }),
            metaService: MetaService(client: { client })))
    }

    private func makeClient() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd.MM.yyyy"
        return f.string(from: now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    AppHeader(client: makeClient())
                    ScreenHead(title: "Home", subtitle: todayLabel)

                    if let error = viewModel.error {
                        AuthAwareError(error: error, onReLogin: {
                            Task { await AuthService(client: { makeClient() }, store: store).logout() }
                        }, onDismiss: {
                            viewModel.error = nil
                        })
                    }

                    if viewModel.isLoading && viewModel.messages.isEmpty
                        && viewModel.homework.isEmpty && viewModel.lessonsToday.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(32)
                    } else {
                        clockCard
                        nowCard
                        if viewModel.settings.ovWetter {
                            wetterCard
                        }
                        messagesSection
                        homeworkSection
                        if !viewModel.cacheInfo.isEmpty {
                            Text(viewModel.cacheInfo)
                                .font(.caption)
                                .foregroundStyle(Color.rMuted)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.rBackground)
            .navigationTitle("Home")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                now = date
            }
        }
    }

    private func nextDetail(_ next: Lesson) -> String {
        var detail = "Als Nächstes: \(next.title ?? "–") (\(next.period ?? "–"). Std · \(next.time ?? "–")"
        if let rooms = next.rooms?.nilIfEmpty { detail += " · Raum \(rooms)" }
        detail += ")"
        return detail
    }

    // MARK: Uhr-Karte (live, deutsches Format) + Aktualisieren

    @ViewBuilder
    private var clockCard: some View {
        EduCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now, style: .time)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Color.rInk)
                    Text(now, style: .date)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rMuted)
                }
                .layoutPriority(1)
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.rInk)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: Jetzt-Karte (aktuelle/nächste Stunde, Primär-Farbe)

    @ViewBuilder
    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STUNDEN HEUTE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.rOnPrimary.opacity(0.7))
            if viewModel.currentLesson == nil && viewModel.nextLesson == nil {
                Text("Schulfrei — kein Unterricht heute.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rOnPrimary)
            } else {
                if let current = viewModel.currentLesson {
                    Text("Jetzt: \(current.title ?? "–") (\(current.period ?? "–"). Std · \(current.time ?? "–"))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rOnPrimary)
                }
                if let next = viewModel.nextLesson {
                    Text(nextDetail(next))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rOnPrimary.opacity(0.75))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Wetterkarte (Schlüssel bleibt serverseitig; Ort per Stadt)

    @ViewBuilder
    private var wetterCard: some View {
        EduCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Wetter")
                    .font(RFont.cardTitle)
                    .foregroundStyle(Color.rInk)
                if let wetter = viewModel.wetter, let today = wetter.today {
                    Text("\(wetter.city ?? "–"): \(today.temp.map { "\($0)°" } ?? "–") · \(today.desc ?? "–")")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.rInk)
                    Text("Max \(today.max.map { "\($0)°" } ?? "–") / Min \(today.min.map { "\($0)°" } ?? "–")"
                        + (today.pop.map { " · Regen \($0) %" } ?? ""))
                        .font(RFont.cardSub)
                        .foregroundStyle(Color.rMuted)
                }
                TextField("Stadt", text: $viewModel.wetterCity)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                Button {
                    Task { await viewModel.loadWetter() }
                } label: {
                    if viewModel.wetterLoading { ProgressView() }
                    else { Text(viewModel.wetter == nil ? "Wetter laden" : "Neu laden") }
                }
                .font(.callout)
                .disabled(viewModel.wetterLoading)
                if viewModel.wetter == nil && viewModel.wetterError == nil && !viewModel.wetterLoading {
                    Text("Noch nicht geladen.")
                        .font(.caption)
                        .foregroundStyle(Color.rMuted)
                }
                if let err = viewModel.wetterError {
                    Text("\(err.message) (\(err.code))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: Nachrichten (neueste, ov_unread-Limit)

    @ViewBuilder
    private var messagesSection: some View {
        HStack {
            SectionLabel(text: "Nachrichten · \(viewModel.messagesTotal)")
            Spacer()
        }
        if viewModel.messages.isEmpty {
            Text("Keine neuen Nachrichten.")
                .font(.callout)
                .foregroundStyle(Color.rMuted)
                .padding(.horizontal, 4)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.messages, id: \.uid) { msg in
                    EduCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(msg.author?.nilIfEmpty ?? "–")
                                .font(RFont.cardTitle)
                                .foregroundStyle(Color.rInk)
                            if let meta = [msg.timestamp, msg.typeLabel]
                                .compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " · ")
                                .nilIfEmpty {
                                Text(meta)
                                    .font(RFont.cardSub)
                                    .foregroundStyle(Color.rMuted)
                            }
                            Text(((msg.text ?? "").prefix(220)) + ((msg.text ?? "").count > 220 ? "…" : ""))
                                .font(.callout)
                                .foregroundStyle(Color.rInk)
                        }
                    }
                }
            }
        }
    }

    // MARK: Hausaufgaben (offen, ov_homework-Limit + Zähler)

    @ViewBuilder
    private var homeworkSection: some View {
        HStack {
            SectionLabel(text: "\(viewModel.homeworkCounts.offen) offen · \(viewModel.homeworkCounts.ueberfaellig) überfällig")
            Spacer()
        }
        if viewModel.homework.isEmpty {
            Text("Keine offenen Hausaufgaben. Sehr gut.")
                .font(.callout)
                .foregroundStyle(Color.rMuted)
                .padding(.horizontal, 4)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.homework, id: \.uid) { hw in
                    EduCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hw.title?.nilIfEmpty ?? "Hausaufgabe #\(hw.uid)")
                                .font(RFont.cardTitle)
                                .foregroundStyle(Color.rInk)
                            Text("\(hw.status ?? "–")"
                                + ((hw.dueDisplay?.nilIfEmpty).map { " · fällig: \($0)" } ?? "")
                                + ((hw.subject?.nilIfEmpty).map { " · \($0)" } ?? ""))
                                .font(RFont.cardSub)
                                .foregroundStyle(Color.rMuted)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Kleine Helfer (genutzt von mehreren Features)

extension String {
    /// nil, wenn leer (für optionale Anzeige-Bausteine).
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
