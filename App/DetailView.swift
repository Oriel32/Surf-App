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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One selection behind both charts, so scrubbing either one marks the same
    /// hour on the other. The score curve and the height curve are two views of
    /// a single hour, and letting them disagree about which hour is being read
    /// would defeat the point of showing them together.
    @State private var selectedTime: Date?

    private var theme: Theme { Theme.current(colorScheme) }
    private var unit: HeightUnit { model.settings.heightUnit }

    private var hours: [HourlyForecast] {
        model.hours(for: spot.id, on: day)
    }

    private var selectedHour: HourlyForecast? {
        ChartScrub.hour(at: selectedTime, in: hours)
    }

    /// A faint band, and never the only thing carrying the meaning — the word
    /// travels with it in `NightLegend`.
    private var nightTint: Color { theme.text2.opacity(0.16) }

    /// An explicit y domain for the height chart.
    ///
    /// Needed so the night band can be drawn against a known scale, and worth
    /// having anyway: an automatic domain rescales between days, which makes two
    /// days of very different size draw curves of identical height.
    private var heightDomainMax: Double {
        let peak = hours
            .map { max($0.conditions.waveHeightMeters, $0.conditions.openSeaHeightMeters) }
            .max() ?? 1
        return max(unit.convert(fromMeters: peak) * 1.15, unit.convert(fromMeters: 0.5))
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
                    if let hour = explainedHour { scoreBreakdown(hour) }
                    heightChart
                    if let hour = representative {
                        periodCard(hour)
                        energyCard(hour)
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
            ScrubCallout(hour: selectedHour, emphasis: .score, heightUnit: unit, theme: theme)

            Chart {
                NightShading(hours: hours, yRange: 0...100, colour: nightTint)

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

                if let selectedHour {
                    ScrubMarker(
                        hour: selectedHour,
                        value: Double(selectedHour.score.value),
                        tint: ScoreBand.band(forScore: selectedHour.score.value).colorToken.color,
                        ruleColour: theme.text2.opacity(0.45)
                    )
                }
            }
            .chartXSelection(value: $selectedTime)
            .chartYScale(domain: 0...100)
            .frame(height: 150)
            .appearsGently(reduceMotion)
            // One tick per hour crossed, not one per pixel of travel.
            .sensoryFeedback(.selection, trigger: selectedHour?.conditions.timestamp)

            NightLegend(theme: theme)
        }
    }

    /// The honest move: the raw model value and the transformed one on the same
    /// axes, both labelled. It proves the app did the transformation instead of
    /// reprinting a model, and lets a veteran apply their own judgement.
    private var heightChart: some View {
        AnalyticalCard(title: "גובה: בחוף מול ים פתוח", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                ScrubCallout(hour: selectedHour, emphasis: .height, heightUnit: unit, theme: theme)

                Chart {
                    NightShading(hours: hours, yRange: 0...heightDomainMax, colour: nightTint)

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

                    if let selectedHour {
                        ScrubMarker(
                            hour: selectedHour,
                            value: unit.convert(fromMeters: selectedHour.conditions.waveHeightMeters),
                            tint: Aqua.aqua600,
                            ruleColour: theme.text2.opacity(0.45)
                        )
                    }
                }
                .chartXSelection(value: $selectedTime)
                .chartYScale(domain: 0...heightDomainMax)
                .frame(height: 150)
                .appearsGently(reduceMotion)
                .sensoryFeedback(.selection, trigger: selectedHour?.conditions.timestamp)

                // Drawn by hand rather than left to the automatic legend, so
                // each series keeps the colour it was assigned above.
                HStack(spacing: 16) {
                    LegendSwatch(colour: Aqua.aqua600, label: "בחוף", dashed: false, theme: theme)
                    LegendSwatch(colour: theme.text2, label: "ים פתוח", dashed: true, theme: theme)
                    NightLegend(theme: theme)
                }

                Text("מקדם החשיפה של \(spot.nameHebrew) הוא \(HebrewText.ltr(String(format: "%.2f", spot.exposureCoefficient))) — זה הפער בין שני הקווים.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The hour the breakdown explains: whichever one the finger is on, falling
    /// back to the hour the rest of the screen describes. Scrubbing the curve
    /// therefore re-explains the score as it moves, which is the whole reason to
    /// put the two next to each other.
    private var explainedHour: HourlyForecast? {
        selectedHour ?? representative
    }

    /// Why the score is what it is.
    ///
    /// `MatchScore.components` has been computed since the engine was written
    /// and read by nothing — the score arrived on screen as an assertion. Every
    /// factor is a normalised 0-1 multiplier, so the smallest bar is literally
    /// the thing costing the most, and the sentence underneath names it.
    private func scoreBreakdown(_ hour: HourlyForecast) -> some View {
        let explanation = Translator.explain(hour.score)
        let band = ScoreBand.band(forScore: hour.score.value)

        return AnalyticalCard(title: "ממה מורכב הציון", theme: theme) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HebrewText.ltr(String(hour.score.value)))
                    .font(SurfFont.headline)
                    .foregroundStyle(band.colorToken.color)
                Text(band.hebrew)
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text1)
                Spacer(minLength: 0)
                Text(ClockText.hourMinute(hour.conditions.timestamp))
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            }

            ForEach(explanation.factors, id: \.component) { factor in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(factor.hebrew)
                            .font(SurfFont.label)
                            // The limiting row carries the word too, not only
                            // the warm tint — greyscale must lose nothing.
                            .foregroundStyle(factor.isLimiting ? Aqua.choppy : theme.text2)
                        if factor.isLimiting {
                            Text("מעכב")
                                .font(SurfFont.label)
                                .foregroundStyle(Aqua.choppy)
                        }
                        Spacer(minLength: 0)
                        Text(HebrewText.ltr(String(Int((factor.value * 100).rounded()))))
                            .font(SurfFont.label)
                            .foregroundStyle(theme.text2)
                    }
                    ScoreBar(
                        fraction: factor.value,
                        tint: factor.isLimiting ? Aqua.choppy : Aqua.aqua600,
                        theme: theme
                    )
                }
                .padding(.top, 2)
            }

            if let sentence = explanation.limitingSentenceHebrew {
                Text(sentence)
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                Text("שום גורם לא מושך את הציון למטה בשעה הזו.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Text("כל גורם הוא מכפיל בין 0 ל-100. הציון הוא המכפלה שלהם, ולכן הגורם הנמוך ביותר הוא זה שעולה הכי הרבה.")
                .font(SurfFont.label)
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(breakdownLabel(hour, explanation))
    }

    private func breakdownLabel(
        _ hour: HourlyForecast,
        _ explanation: ScoreExplanation
    ) -> String {
        var parts = ["ממה מורכב הציון", "ציון \(hour.score.value)"]
        parts.append(contentsOf: explanation.factors.map {
            "\($0.hebrew) \(Int(($0.value * 100).rounded()))"
        })
        if let sentence = explanation.limitingSentenceHebrew { parts.append(sentence) }
        return parts.joined(separator: ", ")
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

    /// Wave power — the number Surfline and Magicseaweed lead with, and the one
    /// a sceptical user will cross-check us against. It is also the term that
    /// now drives the Match Score, so showing it is what makes the score
    /// arguable instead of asserted.
    private func energyCard(_ hour: HourlyForecast) -> some View {
        AnalyticalCard(title: "אנרגיית גלים", theme: theme) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HebrewText.ltr(String(format: "%.1f", hour.conditions.energyKilowattsPerMetre)))
                    .font(SurfFont.score)
                    .foregroundStyle(Aqua.aqua600)
                Text("kW/m")
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(theme.text2)
                Spacer(minLength: 0)
            }
            Text("עוצמה נמדדת בגובה בריבוע כפול המחזור, ולכן גל של מטר בעשר שניות חזק בהרבה מגל של מטר בחמש. זה המספר שמניע את הציון.")
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Text("נמדד \(reading.age().ageInWordsHebrew) · \(model.state(for: spot.id).value?.buoyReference?.hebrewSummary ?? reading.stationID)")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                if let reference = model.state(for: spot.id).value?.buoyReference, !reference.isLocal {
                    // The reading validates the open-sea model rather than this
                    // break. Saying so is what makes showing it defensible.
                    Text("מדידה אזורית — מאמתת את המודל בים הפתוח, לא את הגלים בחוף הזה.")
                        .font(SurfFont.meta)
                        .foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .stale(_, let age):
                Text("המצוף אינו מדווח")
                    .font(SurfFont.cardTitle)
                    .foregroundStyle(Aqua.choppy)
                Text("המדידה האחרונה \(age.ageInWordsHebrew). לא מוצגת כמצב נוכחי.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Text("אין מדידה זמינה")
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
