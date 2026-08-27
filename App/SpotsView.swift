import SwiftUI
import SurfCore

/// "Where should I go?" — a different question from Home.
///
/// On a marginal day the useful answer is often "not your usual beach, but
/// Palmachim is working". The per-spot transformation coefficients are exactly
/// what make that comparison meaningful, so the list ranks by the score each
/// beach actually produces rather than listing them alphabetically.
@MainActor
struct SpotsView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var sort: SpotSort = .score

    private var theme: Theme { Theme.current(colorScheme) }

    enum SpotSort: String, CaseIterable, Identifiable {
        case score
        case name
        var id: String { rawValue }
        var hebrew: String { self == .score ? "לפי ציון" : "לפי שם" }
    }

    private var ordered: [Spot] {
        let favourites = model.settings.favouriteSpotIDs
        let base = sort == .score
            ? model.rankedSpots
            : model.spots.sorted { $0.nameHebrew < $1.nameHebrew }
        // Favourites float to the top in either ordering — the whole point of
        // starring a beach is not having to hunt for it.
        return base.sorted { left, right in
            let leftFav = favourites.contains(left.id)
            let rightFav = favourites.contains(right.id)
            if leftFav != rightFav { return leftFav }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ordered) { spot in
                        NavigationLink {
                            DetailView(model: model, spot: spot, day: Date())
                        } label: {
                            SpotRow(
                                spot: spot,
                                hour: model.currentHour(for: spot.id),
                                state: model.state(for: spot.id),
                                isFavourite: model.settings.isFavourite(spot.id),
                                heightUnit: model.settings.heightUnit,
                                theme: theme,
                                toggleFavourite: { model.settings.toggleFavourite(spot.id) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(theme.page.ignoresSafeArea())
            .navigationTitle("חופים")
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("מיון", selection: $sort) {
                        ForEach(SpotSort.allCases) { option in
                            Text(option.hebrew).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Aqua.aqua600)
                }
            }
        }
        .task(id: model.profileKey) {
            await model.loadAll()
        }
    }
}

@MainActor
struct SpotRow: View {
    let spot: Spot
    let hour: HourlyForecast?
    let state: DataState<SpotForecast>
    let isFavourite: Bool
    let heightUnit: HeightUnit
    let theme: Theme
    let toggleFavourite: () -> Void

    private var presentation: ConditionsPresentation? {
        hour.map { Translator.present($0, heightUnit: heightUnit) }
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .foregroundStyle(isFavourite ? Aqua.aqua600 : theme.text2)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavourite ? "הסרה מהמועדפים" : "הוספה למועדפים")

            VStack(alignment: .leading, spacing: 5) {
                Text(spot.nameHebrew)
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text1)

                if let presentation {
                    Text(presentation.waveLine)
                        .font(SurfFont.meta)
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // The same arrow-word-knots readout Home and Week use. The
                    // relation word alone said which way the wind blew but not
                    // how hard, which is half the fact.
                    WrappingRow {
                        SeaStateChip(word: presentation.seaStateHebrew, token: presentation.seaStateToken)
                        if let hour {
                            WindReadout(presentation: presentation, hour: hour, theme: theme)
                        }
                    }
                } else {
                    placeholder
                }
            }

            Spacer(minLength: 0)

            if let hour {
                VStack(spacing: 2) {
                    Text(HebrewText.ltr(String(hour.score.value)))
                        .font(SurfFont.tabular)
                        .foregroundStyle(ScoreBand.band(forScore: hour.score.value).colorToken.color)
                    if !hour.alerts.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Aqua.alert)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(14)
        .tappableRow()
        .surfCard(theme, radius: Metric.innerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel)
    }

    @ViewBuilder
    private var placeholder: some View {
        switch state {
        case .failed:
            Text("לא נטען")
                .font(SurfFont.meta)
                .foregroundStyle(Aqua.choppy)
        default:
            SkeletonBlock(width: 120, height: 10, theme: theme)
        }
    }

    private var rowLabel: String {
        guard let hour, let presentation else { return "\(spot.nameHebrew), טוען" }
        var parts = [
            spot.nameHebrew,
            "ציון \(hour.score.value)",
            presentation.bandHebrew,
            presentation.windSpokenHebrew
        ]
        if !hour.alerts.isEmpty { parts.append("אזהרת בטיחות") }
        if isFavourite { parts.append("מועדף") }
        return parts.joined(separator: ", ")
    }
}
