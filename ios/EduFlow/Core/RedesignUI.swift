import SwiftUI

// MARK: - Redesign-Komponenten aus templates/EduFlow · Weitere App Screens.png
//
// Paket 0, eingefroren. Alte Feature-Views werden in den Paketen A–G
// darauf umgebaut.

/// Kopfzeile: E-Logo + „EduFlow" links, „..."-Menü rechts
/// (Profil-Info + Abmelden; Einstellungen liegt im Mehr-Tab).
struct AppHeader: View {
    @EnvironmentObject var store: TokenStore
    let client: APIClient

    var body: some View {
        HStack(spacing: 8) {
            // Logo etwas kleiner als die alte E-Box; die Glyphe sitzt in
            // der Datei leicht rechts/unten, darum Bild größer zeichnen
            // und versetzt beschneiden (optische Mitte, je 1pt schwarzer
            // Rand bleibt stehen).
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .offset(x: -0.4, y: -0.7)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel("EduFlow-Logo")
            Text("EduFlow")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.rInk)
            Spacer()
            Menu {
                Text("\(store.username) @ \(store.subdomain)")
                Button("Abmelden", role: .destructive) {
                    Task { await AuthService(client: { client }, store: store).logout() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.rInk)
                    .frame(width: 28, height: 28)
            }
        }
    }
}

/// Screen-Kopf: fetter Titel + grauer Untertitel.
struct ScreenHead: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(RFont.screenTitle)
                .foregroundStyle(Color.rInk)
            Text(subtitle)
                .font(RFont.subtitle)
                .foregroundStyle(Color.rMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kapitälchen-Sektionslabel („4 OFFEN · 1 ÜBERFÄLLIG", „FÄCHER", …).
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(RFont.section)
            .tracking(1.2)
            .foregroundStyle(Color.rMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Karte: 16 Radius, 1 Rahmen.
struct EduCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.rCardBorder, lineWidth: 1)
            )
    }
}

/// Suche als Pille mit Lupen-Icon.
struct SearchPill: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.rMuted)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.rCard)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.rCardBorder, lineWidth: 1))
    }
}

/// Filter-Chips in einer Zeile (aktiv = invertiert).
struct FilterChips: View {
    let options: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    let active = opt == selected
                    Text(opt)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? Color.rOnPrimary : Color.rInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? Color.rPrimary : Color.rCard)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(active ? Color.clear : Color.rCardBorder, lineWidth: 1)
                        )
                        .onTapGesture { selected = opt }
                }
            }
        }
    }
}

/// Status-Pill: farbiger Hintergrund (14 % Deckkraft), Kapitälchen.
struct StatusPill: View {
    let text: String
    let dot: Color

    var body: some View {
        Text(text.uppercased())
            .font(RFont.pill)
            .foregroundStyle(dot)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(dot.opacity(0.14))
            .clipShape(Capsule())
    }
}

/// Primär-Button: 52 hoch, volle Breite, Pille.
struct PrimaryButton: View {
    let text: String
    let action: () -> Void
    var disabled = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(RFont.primaryButton)
                .foregroundStyle(Color.rOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(disabled ? Color.rSecondaryFill : Color.rPrimary)
                .clipShape(Capsule())
        }
        .disabled(disabled)
    }
}

/// Avatar-Kreis mit Initialen (40).
struct AvatarDot: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.rSecondaryFill)
                .frame(width: 40, height: 40)
            Text(String(initials.prefix(2)).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.rMuted)
        }
    }
}

/// Ladezustand (zentriert).
struct LoadingBox: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding()
    }
}

/// Fehlertext (zentriert, rot).
struct ErrorBox: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}

/// Leerzustand (zentriert, grau).
struct EmptyBox: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(Color.rMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}
