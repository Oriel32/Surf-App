import SwiftUI
import SurfCore

/// Turns the hourly score curve into a plan. The highest-value line on the
/// screen: it is the difference between a forecast and an answer.
@MainActor
struct BestWindowSection: View {
    let window: SessionWindow?
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .foregroundStyle(theme.text2)
            if let window {
                Text("החלון הטוב היום: \(ClockText.range(window.start, window.end))")
                    .foregroundStyle(theme.text1)
            } else {
                // Saying so plainly beats naming the least-bad hours. A window
                // the app recommends is a window the user will drive to.
                Text("אין היום חלון מומלץ")
                    .foregroundStyle(theme.text2)
            }
            Spacer(minLength: 0)
        }
        .font(SurfFont.cardTitle)
        .padding(16)
        .surfCard(theme, radius: Metric.innerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// Ground truth, and the honest handling of its absence.
///
/// The community distrusts models by default, so this strip is where the app
/// earns credibility — which is exactly why a stale reading must not be dressed
/// up as a live one.
@MainActor
struct BuoySection: View {
    let status: BuoyStatus
    let heightUnit: HeightUnit
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(theme.text2)
            content
            Spacer(minLength: 0)
        }
        .font(SurfFont.meta)
        .padding(16)
        .surfCard(theme, radius: Metric.innerRadius)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .fresh(let reading):
            Text("מדידת מצוף: \(HebrewText.height(reading.significantWaveHeightMeters, unit: heightUnit)) · \(reading.age().ageInWordsHebrew)")
                .foregroundStyle(theme.text1)

        case .stale(_, let age):
            // Deliberately no number. A months-old storm reading rendered as
            // the current sea is the worst bug this app could ship.
            Text("המצוף אינו מדווח — המדידה האחרונה \(age.ageInWordsHebrew)")
                .foregroundStyle(Aqua.choppy)

        case .unavailable:
            Text("אין מצוף בקרבת החוף")
                .foregroundStyle(theme.text2)
        }
    }
}

/// The hero answers yes or no; this answers when.
@MainActor
struct HourlyStrip: View {
    let hours: [HourlyForecast]
    let theme: Theme

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(hours, id: \.conditions.timestamp) { hour in
                    VStack(spacing: 7) {
                        Text(ClockText.hourMinute(hour.conditions.timestamp))
                            .font(SurfFont.label)
                            .foregroundStyle(theme.text2)
                        Text(HebrewText.ltr(String(hour.score.value)))
                            .font(SurfFont.tabular)
                            .foregroundStyle(ScoreBand.band(forScore: hour.score.value).colorToken.color)
                        WindArrow(blowingFromDegrees: hour.conditions.windDirectionDegrees)
                            .font(.caption)
                            .foregroundStyle(theme.text2)
                        if hour.alerts.isEmpty {
                            // Keeps every column the same height so the row of
                            // scores stays on one baseline.
                            Color.clear.frame(width: 1, height: 12)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Aqua.alert)
                        }
                    }
                    .frame(width: 58)
                    .padding(.vertical, 12)
                    .surfCard(theme, radius: Metric.chipRadius)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(ClockText.hourMinute(hour.conditions.timestamp)), ציון \(hour.score.value)"
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }
}

/// The state apps forget, and the one this domain punishes.
@MainActor
struct StaleNotice: View {
    let age: TimeInterval
    let theme: Theme

    var body: some View {
        Label("אין חיבור — התחזית עודכנה \(age.ageInWordsHebrew)", systemImage: "wifi.slash")
            .font(SurfFont.meta)
            .foregroundStyle(Aqua.choppy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                Aqua.choppy.opacity(theme.isDark ? 0.18 : 0.12),
                in: RoundedRectangle(cornerRadius: Metric.chipRadius, style: .continuous)
            )
    }
}

@MainActor
struct LoadingSection: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("טוען תחזית")
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

@MainActor
struct FailureSection: View {
    let reason: String
    let theme: Theme
    let retry: @Sendable () async -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(theme.text2)
            Text("לא הצלחנו להביא תחזית")
                .font(SurfFont.headline)
                .foregroundStyle(theme.text1)
            Text(reason)
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
                .multilineTextAlignment(.center)
            Button("נסה שוב") {
                Task { await retry() }
            }
            .font(SurfFont.cardTitle)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Aqua.aqua600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
