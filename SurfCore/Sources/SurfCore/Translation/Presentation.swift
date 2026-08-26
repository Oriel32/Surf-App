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
}

/// Stage three of the pipeline: `SpotConditions` becomes words, bands and tokens.
///
/// Pure and table-driven throughout. Nothing here reaches for a network, a clock
/// or a locale — the caller passes in what it has, and the same input always
/// produces the same sentence.
public enum Translator {
    public static func present(_ forecast: HourlyForecast) -> ConditionsPresentation {
        present(forecast.conditions, score: forecast.score)
    }

    public static func present(
        _ conditions: SpotConditions,
        score: MatchScore? = nil
    ) -> ConditionsPresentation {
        let heightText = HebrewText.meters(conditions.waveHeightMeters)
        let band = conditions.band
        let knots = conditions.windSpeedKnots
        let direction = CompassPoint.point(forDegrees: conditions.windDirectionDegrees)

        let scoreBand = score.map { ScoreBand.band(forScore: $0.value) }

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
                direction: direction,
                knots: knots
            )
        )
    }

    /// The shape claude.md specifies: one label per card, read as a sentence.
    /// Spoken units and no direction marks — a screen reader announcing `מ׳`
    /// reads a letter, not "metres".
    private static func accessibilityLabel(
        _ conditions: SpotConditions,
        score: MatchScore?,
        band: WaveBand,
        direction: CompassPoint,
        knots: Double
    ) -> String {
        var parts: [String] = []
        if let score {
            parts.append("ציון \(score.value)")
        }
        parts.append(band.hebrew)
        parts.append(HebrewText.spokenMeters(conditions.waveHeightMeters))
        parts.append("רוח \(direction.hebrewAdjective) \(HebrewText.spokenKnots(knots))")
        if conditions.isSynthetic {
            parts.append("נגזר מקומית מהרוח")
        }
        return parts.joined(separator: ", ")
    }
}
