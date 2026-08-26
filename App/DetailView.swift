import Charts
import SwiftUI
import SurfCore

/// Layer 2 — where a sceptical surfer checks the app's work.
///
/// The dual-layer split is a decision split, not a data-volume one. Home answers
/// "do I get in the car?"; this screen answers "is this model right?", which is
/// why it leads with the transformation shown against its own input rather than
/// with a prettier version of the same summary.
@MainActor
struct DetailView: View {
    @Bindable var model: AppModel
    let spot: Spot
    let day: Date

    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var unit: HeightUnit { model.settings.heightUnit }

    private var hours: [HourlyForecast] {
        model.hours(for: spot.id, on: day)
    }

    private var representative: HourlyForecast? {
        let now = Date()
        if Calendar.israelStandard.isDate(day, inSameDayAs: now) {
            return hours.last { $0.conditions.timestamp <= now } ?? hours.first
        }
        return hours.max { $0.score.value < $1.score.value }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if hours.isEmpty {
                    LoadingSection(theme: theme)
                } else {
                    scoreChart
                    heightChart
                    if let hour = representative {
                        periodCard(hour)
                        temperatureCard(hour)
                    }
                    confidenceCard
                    if model.settings.showBuoy { buoyCard }
                    if model.settings.showWebcams { webcamCard }
                    tideCard
                }
            }
            .padding(16)
        }
        .background(theme.page.ignoresSafeArea())
        .navigationTitle(spot.nameHebrew)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Charts

    private var scoreChart: some View {
        AnalyticalCard(title: "ציון לאורך היום", theme: theme) {
            Chart {
                ForEach(hours, id: \.conditions.timestamp) { hour in
                    AreaMark(
                        x: .value("שעה", hour.conditions.timestamp),
                        y: .value("ציון", hour.score.value)
                    )
                    .foregroundStyle(Aqua.aqua500.opacity(0.18))

                    LineMark(
                        x: .value("שעה", hour.conditions.timestamp),
                        y: .value("ציון", hour.score.value)
                    )
                    .foregroundStyle(Aqua.aqua600)
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 150)
        }
    }

    /// The honest move: the raw model value and the transformed one on the same
    /// axes, both labelled. It proves the app did the transformation instead of
    /// reprinting a model, and lets a veteran apply their own judgement.
    private var heightChart: some View {
        AnalyticalCard(title: "גובה: בחוף מול ים פתוח", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Chart {
                    ForEach(hours, id: \.conditions.timestamp) { hour in
                        LineMark(
                            x: .value("שעה", hour.conditions.timestamp),
                            y: .value("גובה", unit.convert(fromMeters: hour.conditions.waveHeightMeters)),
                            series: .value("סדרה", "shore")
                        )
                        .foregroundStyle(Aqua.aqua600)
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("שעה", hour.conditions.timestamp),
                            y: .value("גובה", unit.convert(fromMeters: hour.conditions.openSeaHeightMeters)),
                            series: .value("סדרה", "open")
                        )
                        .foregroundStyle(theme.text2)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 150)

                // Drawn by hand rather than left to the automatic legend, so
                // each series keeps the colour it was assigned above.
                HStack(spacing: 16) {
                    LegendSwatch(colour: Aqua.aqua600, label: "בחוף", dashed: false, theme: theme)
                    LegendSwatch(colour: theme.text2, label: "ים פתוח", dashed: true, theme: theme)
                }

                Text("מקדם החשיפה של \(spot.nameHebrew) הוא \(HebrewText.ltr(String(format: "%.2f", spot.exposureCoefficient))) — זה הפער בין שני הקווים.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cards

    /// The research calls period the true measure of wave quality — the metric
    /// that separates a real forecast from a weather widget. So it gets its own
    /// card rather than a pill beside the sea state.
    private func periodCard(_ hour: HourlyForecast) -> some View {
        AnalyticalCard(title: "מחזור גלים", theme: theme) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HebrewText.ltr(String(format: "%.1f", hour.conditions.periodSeconds)))
                    .font(SurfFont.score)
                    .foregroundStyle(Aqua.aqua600)
                Text("שניות")
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text2)
                Spacer(minLength: 0)
            }
            Text(periodReading(hour.conditions.periodSeconds))
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func periodReading(_ seconds: Double) -> String {
        // Bands from the research: under 5 s is wind slop, 7-9 s is real energy.
        if seconds < 5 { return "מתחת ל-5 שניות — רחש רוח, לא אנרגיה אמיתית." }
        if seconds < 7 { return "מחזור בינוני. הגלים ידחפו, אבל לא בעוצמה." }
        return "מחזור ארוך — אנרגיה אמיתית, גלים מלאים ומהירים."
    }

    private func temperatureCard(_ hour: HourlyForecast) -> some View {
        AnalyticalCard(title: "מים ואוויר", theme: theme) {
            if let water = hour.conditions.seaSurfaceTemperatureC {
                let suit = Wetsuit.recommendation(forWaterTemperatureC: water)
                HStack(spacing: 12) {
                    Label(
                        "\(HebrewText.ltr(String(format: "%.0f", water)))°",
                        systemImage: "water.waves"
                    )
                    if let air = hour.conditions.airTemperatureC {
                        Label(
                            "\(HebrewText.ltr(String(format: "%.0f", air)))°",
                            systemImage: "thermometer.sun"
                        )
                    }
                    Spacer(minLength: 0)
                }
                .font(SurfFont.cardTitle)
                .foregroundStyle(theme.text1)

                Label(suit.hebrew, systemImage: suit.symbolName)
                    .font(SurfFont.meta)
                    .foregroundStyle(Aqua.aqua600)
            } else {
                Text("אין נתוני טמפרטורה לשעה זו")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            }
        }
    }

    /// Confidence is measured, never asserted.
    ///
    /// It comes from the spread between independent models, which needs
    /// Stormglass — and its free tier of roughly ten requests a day cannot be
    /// called from a device. So this says it is unavailable rather than
    /// fabricating a percentage from the single model we do have.
    private var confidenceCard: some View {
        AnalyticalCard(title: "מידת ודאות", theme: theme) {
            if let confidence = model.state(for: spot.id).value?.confidence {
                let percent = Int((confidence * 100).rounded())
                Text("\(HebrewText.ltr(String(percent)))%")
                    .font(SurfFont.headline)
                    .foregroundStyle(confidence > 0.7 ? Aqua.aqua600 : Aqua.choppy)
                Text(confidence > 0.7
                     ? "המודלים מסכימים ביניהם."
                     : "יש פער בין המודלים — התחזית פחות ודאית.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            } else {
                Text("לא זמין — נדרש מקור נתונים שני")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buoyCard: some View {
        AnalyticalCard(title: "מדידה בזמן אמת", theme: theme) {
            switch model.state(for: spot.id).value?.buoy ?? .unavailable {
            case .fresh(let reading):
                Text("\(HebrewText.height(reading.significantWaveHeightMeters, unit: unit)) · \(HebrewText.ltr(String(format: "%.1f", reading.peakPeriodSeconds))) שניות")
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text1)
                Text("נמדד \(reading.age().ageInWordsHebrew) · תחנת \(reading.stationID)")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            case .stale(_, let age):
                Text("המצוף אינו מדווח")
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(Aqua.choppy)
                Text("המדידה האחרונה \(age.ageInWordsHebrew). לא מוצגת כמצב נוכחי.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Text("אין מצוף בקרבת החוף")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            }
        }
    }

    private var webcamCard: some View {
        AnalyticalCard(title: "מצלמות חוף", theme: theme) {
            Text("לא מוגדרת מצלמה לחוף זה.")
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
        }
    }

    /// Present, and low in the hierarchy — matching its low relevance in the
    /// Mediterranean, where the range is a few dozen centimetres.
    private var tideCard: some View {
        AnalyticalCard(title: "גאות ושפל", theme: theme) {
            if let level = representative?.conditions.seaLevelMeters {
                Text("\(HebrewText.height(level, unit: unit)) מעל הממוצע")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text1)
            } else {
                Text("אין נתוני מפלס לשעה זו")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            }
        }
    }
}

@MainActor
struct AnalyticalCard<Content: View>: View {
    let title: String
    let theme: Theme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SurfFont.label)
                .foregroundStyle(theme.text2)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surfCard(theme, radius: Metric.innerRadius)
    }
}

@MainActor
struct LegendSwatch: View {
    let colour: Color
    let label: String
    let dashed: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(dashed ? colour.opacity(0.55) : colour)
                .frame(width: 18, height: 3)
            Text(label)
                .font(SurfFont.label)
                .foregroundStyle(theme.text2)
        }
    }
}
