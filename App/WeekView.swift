import SwiftUI
import SurfCore

/// Seven days, one row each — scannable in a single pass down the screen.
///
/// **Never a daily average.** A day that is glassy at dawn and blown out by noon
/// averages to a middle number that is wrong at every hour it claims to
/// describe. Each row is a promise about a *time of day*: its best window and
/// the peak that window produces.
@MainActor
struct WeekView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    switch model.selectedState {
                    case .loading:
                        LoadingSection(theme: theme)
                    case .failed(let reason):
                        FailureSection(reason: reason, theme: theme) { [model] in
                            await model.loadSelected()
                        }
                    case .loaded:
                        rows
                    case .stale(_, let age):
                        StaleNotice(age: age, theme: theme)
                        rows
                    }
                }
                .padding(16)
            }
            .background(theme.page.ignoresSafeArea())
            .navigationTitle("שבוע")
            .refreshable { await model.refreshSelected() }
            .toolbar { spotPicker }
        }
        .task(id: model.reloadKey) {
            await model.loadSelected()
        }
    }

    private var days: [(day: Date, window: SessionWindow?, peakScore: Int)] {
        model.days(for: model.selectedSpotID)
    }

    /// The highest score across the whole week, so each row's bar is drawn
    /// relative to the best day rather than to an absolute 100 — which is what
    /// makes "Thursday is the day" visible without reading a number.
    private var weekPeak: Int {
        max(days.map(\.peakScore).max() ?? 0, 1)
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(days, id: \.day) { entry in
            NavigationLink {
                if let spot = model.selectedSpot {
                    DetailView(model: model, spot: spot, day: entry.day)
                }
            } label: {
                WeekRow(
                    day: entry.day,
                    window: entry.window,
                    peakScore: entry.peakScore,
                    weekPeak: weekPeak,
                    peakHour: peakHour(on: entry.day),
                    heightUnit: model.settings.heightUnit,
                    theme: theme
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// The hour the row is actually a promise about.
    private func peakHour(on day: Date) -> HourlyForecast? {
        model.hours(for: model.selectedSpotID, on: day)
            .max { $0.score.value < $1.score.value }
    }

    @ToolbarContentBuilder
    private var spotPicker: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("חוף", selection: $model.selectedSpotID) {
                    ForEach(model.spots) { spot in
                        Text(spot.nameHebrew).tag(spot.id)
                    }
                }
            } label: {
                Image(systemName: "mappin.and.ellipse")
            }
            .accessibilityLabel("בחירת חוף")
        }
    }
}

@MainActor
struct WeekRow: View {
    let day: Date
    let window: SessionWindow?
    let peakScore: Int
    let weekPeak: Int
    let peakHour: HourlyForecast?
    let heightUnit: HeightUnit
    let theme: Theme

    private var band: ScoreBand { ScoreBand.band(forScore: peakScore) }

    private var presentation: ConditionsPresentation? {
        peakHour.map { Translator.present($0, heightUnit: heightUnit) }
    }

    private var hasAlert: Bool {
        !(peakHour?.alerts.isEmpty ?? true)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ClockText.weekdayHebrew(day))
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text1)
                Text(ClockText.dayMonth(day))
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            }
            .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(HebrewText.ltr(String(peakScore)))
                        .font(SurfFont.tabular)
                        .foregroundStyle(band.colorToken.color)

                    // The safety glyph appears on every affected row, not only
                    // on Home.
                    if hasAlert {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Aqua.alert)
                            .accessibilityHidden(true)
                    }

                    if let presentation {
                        Text(presentation.waveLine)
                            .font(SurfFont.meta)
                            .foregroundStyle(theme.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                // The bar is the trend: drawn against the week's best day, so
                // the strongest day stands out without reading any numbers.
                ScoreBar(fraction: Double(peakScore) / Double(weekPeak), tint: band.colorToken.color, theme: theme)

                Text(window.map { ClockText.range($0.start, $0.end) } ?? "אין חלון מומלץ")
                    .font(SurfFont.label)
                    .foregroundStyle(window == nil ? theme.text2 : Aqua.aqua600)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.footnote)
                .foregroundStyle(theme.text2)
                .flipsForRightToLeftLayoutDirection(true)
        }
        .padding(16)
        .tappableRow()
        .surfCard(theme, radius: Metric.innerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel)
    }

    private var rowLabel: String {
        var parts = [ClockText.weekdayHebrew(day), "ציון \(peakScore)"]
        if let presentation { parts.append(presentation.bandHebrew) }
        if let window {
            parts.append("החלון \(ClockText.hourMinute(window.start)) עד \(ClockText.hourMinute(window.end))")
        } else {
            parts.append("אין חלון מומלץ")
        }
        if hasAlert { parts.append("אזהרת בטיחות") }
        return parts.joined(separator: ", ")
    }
}

/// A hairline bar. Deliberately not a sparkline: the row carries one number,
/// and a curve would imply a precision the daily peak does not have.
@MainActor
struct ScoreBar: View {
    let fraction: Double
    let tint: Color
    let theme: Theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
