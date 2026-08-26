import Foundation

/// 0–100 for the selected sport.
///
/// The point is to spare the user from mentally combining height, period, wind
/// strength and wind direction every morning. The weights invert between sports
/// on purpose: a 20-knot onshore day is a ruined surf session and a good kite
/// session, and one number has to say so.
///
/// ## Why wind gates rather than adds
/// A plain weighted sum lets good size and period carry a ruined day — perfect
/// 0.9 m at 8 s in a 20-knot onshore would score about 70, and nobody surfs
/// that. Wind is therefore a multiplier on wave quality for surfing, and on
/// everything for the wind sports. Conditions that destroy a session must be
/// able to destroy the score.
public enum MatchScoreEngine {
    public static func score(for conditions: SpotConditions, profile: UserProfile) -> MatchScore {
        let (raw, components) = rawScore(conditions, sport: profile.sport)
        let suppressed = raw * safetyMultiplier(conditions, profile: profile)
        let value = Int((suppressed * 100).rounded())
        return MatchScore(
            value: max(0, min(100, value)),
            sport: profile.sport,
            components: components
        )
    }

    private static func rawScore(
        _ conditions: SpotConditions,
        sport: Sport
    ) -> (value: Double, components: [String: Double]) {
        switch sport {
        case .surfing:
            return surfing(conditions)
        case .kitesurfing:
            return windSport(conditions, tuning: ScoreTuning.kitesurfing)
        case .wingFoil:
            return windSport(conditions, tuning: ScoreTuning.wingFoil)
        case .sup:
            return standUpPaddle(conditions)
        }
    }

    // MARK: - Surfing

    private static func surfing(_ c: SpotConditions) -> (Double, [String: Double]) {
        let tuning = ScoreTuning.surfing
        let height = tuning.height.value(c.waveHeightMeters)
        let period = tuning.period.value(c.periodSeconds)
        let wind = tuning.wind[c.windRelation].value(c.windSpeedKnots)

        // Period modulates size rather than standing in for it. Adding the two
        // would let a dead flat sea with a long period score 40/100, because
        // nothing about a 12-second period helps when there is no wave.
        let waveQuality = height * (tuning.periodFloor + (1 - tuning.periodFloor) * period)

        let value = waveQuality * (tuning.windFloor + (1 - tuning.windFloor) * wind)
        return (value, ["height": height, "period": period, "wind": wind])
    }

    // MARK: - Kite and wing foil

    private static func windSport(
        _ c: SpotConditions,
        tuning: ScoreTuning.WindSport
    ) -> (Double, [String: Double]) {
        let wind = tuning.wind.value(c.windSpeedKnots)
        let direction = tuning.direction[c.windRelation]
        let height = tuning.height.value(c.waveHeightMeters)

        // No wind means no session, whatever else is true.
        let value = wind
            * (tuning.directionFloor + (1 - tuning.directionFloor) * direction)
            * (tuning.heightFloor + (1 - tuning.heightFloor) * height)
        return (value, ["wind": wind, "direction": direction, "height": height])
    }

    // MARK: - SUP

    private static func standUpPaddle(_ c: SpotConditions) -> (Double, [String: Double]) {
        let tuning = ScoreTuning.sup
        let flatness = tuning.flatness.value(c.waveHeightMeters)
        let wind = tuning.wind.value(c.windSpeedKnots)

        let value = flatness * (tuning.windFloor + (1 - tuning.windFloor) * wind)
        return (value, ["flatness": flatness, "wind": wind])
    }

    // MARK: - Safety suppression

    /// A score must never invite someone into water that is dangerous for them.
    ///
    /// An offshore wind produces a beautiful, glassy, high-scoring sea *and* a
    /// drift hazard at the same time. For the users the hazard actually applies
    /// to, the score is crushed rather than merely annotated — a banner beside a
    /// 90 is an argument the banner loses.
    private static func safetyMultiplier(_ c: SpotConditions, profile: UserProfile) -> Double {
        let alerts = SafetyEngine.alerts(for: c, profile: profile)
        guard let worst = alerts.map(\.severity).max() else { return 1 }

        // Anyone on a floating craft is held to the harshest multiplier: a SUP
        // is a sail and cannot be duck-dived under a gust.
        return ScoreTuning.suppression.multiplier(
            for: worst,
            onFloatingCraft: profile.sport == .sup
        )
    }
}
