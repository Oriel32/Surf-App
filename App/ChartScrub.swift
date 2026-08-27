import Charts
import SwiftUI
import SurfCore

/// Touch handling for the analytical charts.
///
/// ## Why this uses `chartXSelection` and not a `DragGesture`
/// The obvious implementation — a drag gesture, `location.x / width`, index into
/// the array — is wrong in this app specifically. `GlassyApp` forces
/// `\.layoutDirection` to `.rightToLeft` for the whole process, and under RTL
/// that arithmetic silently inverts: the finger moves toward dawn and the
/// readout walks toward dusk. Nothing crashes and nothing looks broken, which is
/// what makes it dangerous.
///
/// `chartXSelection` resolves the touch through the chart's own coordinate
/// space, so it stays correct in either direction and needs no mirroring code of
/// its own.
enum ChartScrub {
    /// The hour a selection landed on.
    ///
    /// Nearest-neighbour rather than a truncating lookup, because the selection
    /// is a continuous position on the axis and a touch between 07:00 and 08:00
    /// should resolve to whichever it is actually closer to.
    static func hour(at date: Date?, in hours: [HourlyForecast]) -> HourlyForecast? {
        guard let date else { return nil }
        return hours.min {
            abs($0.conditions.timestamp.timeIntervalSince(date))
                < abs($1.conditions.timestamp.timeIntervalSince(date))
        }
    }
}

/// What the callout leads with. Each chart answers its own question first, so
/// the readout beside the score curve leads with the score and the one beside
/// the height curve leads with the height.
enum ScrubEmphasis {
    case score
    case height
}

/// The floating readout that follows a scrub.
///
/// Occupies its full height whether or not anything is selected. A callout that
/// appears from nothing shoves the chart down under the finger that summoned it,
/// which makes the chart feel like it is dodging the touch. When idle it carries
/// the invitation instead — otherwise nothing on screen says the chart can be
/// touched at all.
@MainActor
struct ScrubCallout: View {
    let hour: HourlyForecast?
    let emphasis: ScrubEmphasis
    let heightUnit: HeightUnit
    let theme: Theme

    private var presentation: ConditionsPresentation? {
        hour.map { Translator.present($0, heightUnit: heightUnit) }
    }

    var body: some View {
        Group {
            if let hour, let presentation {
                reading(hour, presentation)
            } else {
                Text("החליקו אצבע על התרשים לפרטי כל שעה")
                    .font(SurfFont.label)
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func reading(
        _ hour: HourlyForecast,
        _ presentation: ConditionsPresentation
    ) -> some View {
        // Wraps rather than truncates: at accessibility sizes the readout is
        // taller than the chart, and that is the correct trade.
        WrappingRow {
            Text(ClockText.hourMinute(hour.conditions.timestamp))
                .font(SurfFont.tabular)
                .foregroundStyle(theme.text1)

            switch emphasis {
            case .score:
                Text(presentation.scoreText ?? "—")
                    .font(SurfFont.tabular)
                    .foregroundStyle(presentation.scoreToken?.color ?? theme.text2)
                Text(presentation.waveLine)
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

            case .height:
                Text(presentation.waveLine)
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("ים פתוח \(HebrewText.height(hour.conditions.openSeaHeightMeters, unit: heightUnit))")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Wind rides in both callouts. It is the fact that decides whether
            // a given hour is worth driving to, and the charts do not plot it.
            WindReadout(presentation: presentation, hour: hour, theme: theme)
        }
    }
}

/// The dashed rule and dot that mark the scrubbed hour.
///
/// A `ChartContent` builder rather than a `View`, so it composes into a `Chart`
/// alongside the series instead of being overlaid on top of one.
struct ScrubMarker: ChartContent {
    let hour: HourlyForecast
    /// Where on the y axis to sit the dot — whatever the host chart plots.
    let value: Double
    let tint: Color
    let ruleColour: Color

    var body: some ChartContent {
        RuleMark(x: .value("שעה", hour.conditions.timestamp))
            .foregroundStyle(ruleColour)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

        PointMark(
            x: .value("שעה", hour.conditions.timestamp),
            y: .value("ערך", value)
        )
        .foregroundStyle(tint)
        .symbolSize(80)
    }
}

/// Dims the hours the window finder refuses to recommend.
///
/// Both day charts plot all 24 hours, so a high score at 03:00 draws a peak the
/// app will never suggest — `WindowFinder` drops non-daylight hours from every
/// window and every daily peak. Shading them is how the chart stops contradicting
/// the sentence above it.
///
/// One rectangle per dark hour rather than per contiguous run: the series is
/// hourly and gapless, so adjacent rectangles abut and read as one band, and the
/// run-detection that would replace this is code that can be wrong.
struct NightShading: ChartContent {
    let hours: [HourlyForecast]
    /// The host chart's y domain. Stated rather than left to span implicitly,
    /// so the band is pinned to the same scale the series are drawn against.
    let yRange: ClosedRange<Double>
    let colour: Color

    var body: some ChartContent {
        ForEach(hours.filter { !$0.conditions.isDaylight }, id: \.conditions.timestamp) { hour in
            RectangleMark(
                xStart: .value("מ", hour.conditions.timestamp),
                xEnd: .value("עד", hour.conditions.timestamp.addingTimeInterval(3600)),
                yStart: .value("מ", yRange.lowerBound),
                yEnd: .value("עד", yRange.upperBound)
            )
            .foregroundStyle(colour)
        }
    }
}

/// Names the shading in words.
///
/// Colour reinforces, it never carries — a greyscale reader gets a faint band
/// and no explanation without this line.
@MainActor
struct NightLegend: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.text2.opacity(0.16))
                .frame(width: 18, height: 10)
            Text("שעות חשיכה")
                .font(SurfFont.label)
                .foregroundStyle(theme.text2)
        }
        .accessibilityHidden(true)
    }
}
