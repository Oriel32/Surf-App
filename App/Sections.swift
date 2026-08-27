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
    /// Where the buoy is relative to this beach. Israel has one live wave buoy,
    /// so most spots are reading a measurement from up or down the coast — and
    /// the distance is what keeps showing it honest.
    let reference: BuoyReference?
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
            VStack(alignment: .leading, spacing: 2) {
                Text("\(HebrewText.height(reading.significantWaveHeightMeters, unit: heightUnit)) · \(reading.age().ageInWordsHebrew)")
                    .foregroundStyle(theme.text1)
                if let reference {
                    Text(reference.hebrewSummary)
                        .font(SurfFont.label)
                        .foregroundStyle(theme.text2)
                }
            }

        case .stale(_, let age):
            // Deliberately no number. A months-old storm reading rendered as
            // the current sea is the worst bug this app could ship.
            Text("המצוף אינו מדווח — המדידה האחרונה \(age.ageInWordsHebrew)")
                .foregroundStyle(Aqua.choppy)

        case .unavailable:
            Text("אין מדידה זמינה")
                .foregroundStyle(theme.text2)
        }
    }
}

/// The hero answers yes or no; this answers when.
@MainActor
struct HourlyStrip: View {
    let hours: [HourlyForecast]
    /// The day's recommended window, so the strip can show *where* it falls
    /// rather than leaving the sentence above it to be taken on trust.
    let window: SessionWindow?
    let theme: Theme

    /// Anchors the strip on the hour the user is standing in.
    ///
    /// Opening a 24-column strip at midnight and asking a half-awake surfer to
    /// scroll to now is the sort of small tax that makes an app feel like work.
    @State private var anchor: Date?

    private var currentHour: HourlyForecast? {
        let now = Date()
        return hours.last { $0.conditions.timestamp <= now } ?? hours.first
    }

    private func isInWindow(_ hour: HourlyForecast) -> Bool {
        guard let window else { return false }
        let stamp = hour.conditions.timestamp
        return stamp >= window.start && stamp < window.end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(hours, id: \.conditions.timestamp) { hour in
                        column(hour)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 14)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // Hours snap into place rather than drifting to rest halfway
            // through a column.
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $anchor, anchor: .center)
            .onAppear { anchor = currentHour?.conditions.timestamp }
            // A new day's forecast re-anchors instead of leaving the strip
            // parked on an hour that has since passed.
            .onChange(of: hours.first?.conditions.timestamp) {
                anchor = currentHour?.conditions.timestamp
            }

            if window != nil {
                // The tint means nothing on its own in greyscale, so the word
                // travels with it.
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Aqua.aqua500.opacity(0.22))
                        .frame(width: 18, height: 10)
                    Text("החלון המומלץ")
                        .font(SurfFont.label)
                        .foregroundStyle(theme.text2)
                }
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func column(_ hour: HourlyForecast) -> some View {
        let isNow = hour.conditions.timestamp == currentHour?.conditions.timestamp
        let inWindow = isInWindow(hour)

        VStack(spacing: 7) {
            Text(isNow ? "עכשיו" : ClockText.hourMinute(hour.conditions.timestamp))
                .font(SurfFont.label)
                .foregroundStyle(isNow ? Aqua.aqua600 : theme.text2)
            Text(HebrewText.ltr(String(hour.score.value)))
                .font(SurfFont.tabular)
                .foregroundStyle(ScoreBand.band(forScore: hour.score.value).colorToken.color)
            // Arrow and speed together. The arrow alone says which way but not
            // whether it matters, and 4 knots offshore and 20 knots offshore
            // are opposite mornings.
            WindArrow(blowingFromDegrees: hour.conditions.windDirectionDegrees)
                .font(.caption)
                .foregroundStyle(theme.text2)
            Text(HebrewText.knots(hour.conditions.windSpeedKnots))
                .font(SurfFont.label)
                .foregroundStyle(theme.text2)
                .lineLimit(1)
            if hour.alerts.isEmpty {
                // Keeps every column the same height so the row of scores stays
                // on one baseline.
                Color.clear.frame(width: 1, height: 12)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Aqua.alert)
            }
        }
        .frame(width: 66)
        .padding(.vertical, 12)
        .background(
            inWindow ? Aqua.aqua500.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: Metric.chipRadius, style: .continuous)
        )
        .surfCard(theme, radius: Metric.chipRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(columnLabel(hour, isNow: isNow, inWindow: inWindow))
    }

    private func columnLabel(
        _ hour: HourlyForecast,
        isNow: Bool,
        inWindow: Bool
    ) -> String {
        var parts = [ClockText.hourMinute(hour.conditions.timestamp)]
        if isNow { parts.append("השעה הנוכחית") }
        parts.append("ציון \(hour.score.value)")
        parts.append(Translator.present(hour).windSpokenHebrew)
        if inWindow { parts.append("בתוך החלון המומלץ") }
        if !hour.alerts.isEmpty { parts.append("אזהרת בטיחות") }
        return parts.joined(separator: ", ")
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

/// Loading, in the shape of the screen that is arriving.
///
/// Was a bare `ProgressView`, which collapsed the whole layout to a dot and then
/// snapped it back — and `surf-ui` rules out a spinner wherever something more
/// useful can stand in its place. Holding the geometry means nothing jumps when
/// the forecast lands.
@MainActor
struct LoadingSection: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 14) {
            // The hero card.
            VStack(alignment: .leading, spacing: 16) {
                SkeletonBlock(width: 92, height: 34, theme: theme)
                SkeletonBlock(width: 180, height: 18, theme: theme)
                HStack(spacing: 12) {
                    SkeletonBlock(width: 64, height: 24, theme: theme)
                    SkeletonBlock(width: 110, height: 24, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .surfCard(theme)

            // The best-window line.
            SkeletonBlock(width: 210, height: 16, theme: theme)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfCard(theme, radius: Metric.innerRadius)

            // The hourly strip.
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBlock(width: 66, height: 96, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("טוען תחזית")
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
