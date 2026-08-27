import Foundation

/// Everything a card needs to render one hour, already worded.
///
/// The pipeline is `raw ingest -> spot transform -> translate`, and this is the
/// output of the third stage. Keeping it a separate stage rather than letting
/// views format numbers is what makes the product vocabulary testable: the rule
/// that height is **never** shown without its slang is enforced here, once, by
/// construction — `waveLine` cannot be built without both halves.
public struct ConditionsPresentation: Sendable, Equatable {
    /// `0.8 מ׳ · מותן עד חזה`. Metric and slang together, always.
    public let waveLine: String
    public let waveHeightText: String
    public let bandHebrew: String
    public let bandEnglish: String

    public let seaStateHebrew: String
    public let seaStateToken: ColorToken

    /// `רוח מזרחית 8 קשר`.
    public let windLine: String
    /// The same wind spelled out for VoiceOver: `רוח מזרחית 8 קשר` with spoken
    /// units and no bidi isolates, which a screen reader reads as punctuation.
    ///
    /// Built here rather than in each row so that every surface announcing wind
    /// announces it identically — Home, Week and Spots all read from this.
    public let windSpokenHebrew: String
    /// `מהיבשה`. The word that changes behaviour, kept separate because it
    /// outranks the arrow and the number in the layout.
    public let windRelationHebrew: String
    public let windStrength: WindStrength
    public let windDirection: CompassPoint

    public let scoreText: String?
    public let scoreBand: ScoreBand?
    public let scoreToken: ColorToken?

    /// Present only for the Gulf of Eilat, where values are synthesised from
    /// local wind because no wave model resolves the basin. It is not optional
    /// styling: wherever these numbers appear, this label appears with them.
    public let derivationNoticeHebrew: String?

    /// One coherent sentence, not six fragments. VoiceOver reads meaning.
    public let accessibilityLabel: String

    /// Wave power in kW/m, for the analytical layer. Height alone cannot
    /// separate a groundswell from chop; this is the number that can.
    public let energyText: String
}

/// A Match Score with its reasoning, ready to render.
///
/// "82" is an assertion. "82, held back by the period" is an argument the user
/// can check against the sea in front of them — and this app's whole thesis is
/// that a number nobody can argue with is a number nobody will trust.
public struct ScoreExplanation: Sendable, Equatable {
    /// Every factor the engine reported, in a stable per-sport order. Values are
    /// normalised 0-1, so they render directly as bar fractions.
    public let factors: [Factor]

    /// The weakest factor, when one is genuinely weak enough to blame.
    ///
    /// `nil` when nothing is dragging: on a good day the honest answer is that
    /// the score is high because everything is fine, and inventing a culprit
    /// would teach the user to distrust the one that appears on a bad day.
    public let limitingFactor: ScoreComponent?
    public let limitingSentenceHebrew: String?

    public struct Factor: Sendable, Equatable {
        public let component: ScoreComponent
        /// 0-1.
        public let value: Double
        public let hebrew: String
        /// True for `limitingFactor`, so the view highlights one row without
        /// re-deriving which one.
        public let isLimiting: Bool
    }

    /// Below this, a factor is weak enough to be worth naming. Above it, the
    /// aspect is doing its job and pointing at it would be noise.
    public static let limitingThreshold = 0.7
}

/// Stage three of the pipeline: `SpotConditions` becomes words, bands and tokens.
///
/// Pure and table-driven throughout. Nothing here reaches for a network, a clock
/// or a locale — the caller passes in what it has, and the same input always
/// produces the same sentence.
public enum Translator {
    public static func present(
        _ forecast: HourlyForecast,
        heightUnit: HeightUnit = .meters
    ) -> ConditionsPresentation {
        present(forecast.conditions, score: forecast.score, heightUnit: heightUnit)
    }

    public static func present(
        _ conditions: SpotConditions,
        score: MatchScore? = nil,
        heightUnit: HeightUnit = .meters
    ) -> ConditionsPresentation {
        // A range, not a single number: the significant height through to the
        // sets. This is what "2-3 ft" means on every other forecast, and
        // quoting only the significant height reads a size smaller than the
        // app a user is cross-checking against.
        let range = conditions.surfRange
        let heightText = HebrewText.heightRange(
            range.significantMeters, range.setMeters, unit: heightUnit
        )
        let band = conditions.band
        let knots = conditions.windSpeedKnots
        let direction = CompassPoint.point(forDegrees: conditions.windDirectionDegrees)

        let scoreBand = score.map { ScoreBand.band(forScore: $0.value) }
        let windSpoken = "רוח \(direction.hebrewAdjective) \(HebrewText.spokenKnots(knots))"

        return ConditionsPresentation(
            // The middle dot keeps the two halves visually distinct without
            // implying one is a parenthetical of the other. Both are the answer.
            waveLine: "\(heightText) · \(band.hebrew)",
            waveHeightText: heightText,
            bandHebrew: band.hebrew,
            bandEnglish: band.english,
            seaStateHebrew: conditions.seaState.hebrew,
            seaStateToken: conditions.seaState.colorToken,
            windLine: "רוח \(direction.hebrewAdjective) \(HebrewText.knots(knots))",
            windSpokenHebrew: windSpoken,
            windRelationHebrew: conditions.windRelation.hebrew,
            windStrength: WindStrength.strength(forKnots: knots),
            windDirection: direction,
            scoreText: score.map { HebrewText.ltr(String($0.value)) },
            scoreBand: scoreBand,
            scoreToken: scoreBand?.colorToken,
            derivationNoticeHebrew: conditions.isSynthetic
                ? "נגזר מקומית מהרוח, לא ממודל גלים"
                : nil,
            accessibilityLabel: accessibilityLabel(
                conditions,
                score: score,
                band: band,
                windSpoken: windSpoken,
                heightUnit: heightUnit
            ),
            energyText: HebrewText.ltr(String(format: "%.1f", conditions.energyKilowattsPerMetre))
        )
    }

    /// Turns a score's raw factors into something a sceptic can read.
    ///
    /// Ordering comes from `ScoreComponent.order(for:)` rather than from the
    /// dictionary, which has none — iterating `components` directly would shuffle
    /// the rows on every redraw. Any key the engine emits that this does not know
    /// about is dropped rather than shown untranslated.
    public static func explain(_ score: MatchScore) -> ScoreExplanation {
        let ordered = ScoreComponent.order(for: score.sport)
            .compactMap { component -> (ScoreComponent, Double)? in
                score.components[component.rawValue].map { (component, $0) }
            }

        // The weakest factor, and only if it is actually weak. The score is the
        // product of these, so the minimum is what is costing the most.
        let weakest = ordered.min { $0.1 < $1.1 }
        let limiting = (weakest?.1 ?? 1) < ScoreExplanation.limitingThreshold
            ? weakest?.0
            : nil

        return ScoreExplanation(
            factors: ordered.map { component, value in
                ScoreExplanation.Factor(
                    component: component,
                    value: value,
                    hebrew: component.hebrew,
                    isLimiting: component == limiting
                )
            },
            limitingFactor: limiting,
            limitingSentenceHebrew: limiting?.limitingSentenceHebrew
        )
    }

    /// The shape claude.md specifies: one label per card, read as a sentence.
    /// Spoken units and no direction marks — a screen reader announcing `מ׳`
    /// reads a letter, not "metres".
    private static func accessibilityLabel(
        _ conditions: SpotConditions,
        score: MatchScore?,
        band: WaveBand,
        windSpoken: String,
        heightUnit: HeightUnit
    ) -> String {
        var parts: [String] = []
        if let score {
            parts.append("ציון \(score.value)")
        }
        parts.append(band.hebrew)
        // A screen reader gets one number, not a range: the sets, which is what
        // a surfer would answer if asked how big it was.
        parts.append(HebrewText.spokenHeight(conditions.surfRange.setMeters, unit: heightUnit))
        parts.append(windSpoken)
        if conditions.isSynthetic {
            parts.append("נגזר מקומית מהרוח")
        }
        return parts.joined(separator: ", ")
    }
}
