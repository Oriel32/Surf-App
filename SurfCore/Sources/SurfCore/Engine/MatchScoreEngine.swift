import Foundation

/// A ramp-up, plateau, ramp-down response curve.
///
/// Almost every term in this model has the same shape: too little is bad, too
/// much is bad, there is a band in the middle that is ideal. Expressing that
/// once keeps the sport profiles declarative instead of branchy.
struct Trapezoid: Sendable {
    let riseStart: Double
    let plateauStart: Double
    let plateauEnd: Double
    let fallEnd: Double

    /// 0...1.
    func value(_ x: Double) -> Double {
        if x <= riseStart || x >= fallEnd { return 0 }
        if x >= plateauStart && x <= plateauEnd { return 1 }
        if x < plateauStart {
            return (x - riseStart) / max(1e-9, plateauStart - riseStart)
        }
        return (fallEnd - x) / max(1e-9, fallEnd - plateauEnd)
    }
}

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
            return windSport(conditions, idealLow: 15, idealHigh: 22)
        case .wingFoil:
            return windSport(conditions, idealLow: 12, idealHigh: 22)
        case .sup:
            return standUpPaddle(conditions)
        }
    }

    // MARK: - Surfing

    private static func surfing(_ c: SpotConditions) -> (Double, [String: Double]) {
        // Full marks between 0.6 m and 1.5 m at the beach — the golden range.
        let height = Trapezoid(riseStart: 0.25, plateauStart: 0.6, plateauEnd: 1.5, fallEnd: 3.0)
            .value(c.waveHeightMeters)

        // Period is the true measure of wave quality. Under 5 s is wind slop
        // that will not carry a board; 7–9 s is real energy.
        let period = Trapezoid(riseStart: 3.5, plateauStart: 7.0, plateauEnd: 12.0, fallEnd: 20.0)
            .value(c.periodSeconds)

        let wind = surfingWindTerm(c)

        // Period modulates size rather than standing in for it. Adding the two
        // would let a dead flat sea with a long period score 40/100, because
        // nothing about a 12-second period helps when there is no wave.
        let waveQuality = height * (0.35 + 0.65 * period)

        // The floor of 0.15 keeps a genuinely big, long-period day from reading
        // as a flat zero just because it is blown out — it is still worth
        // knowing the swell arrived.
        let value = waveQuality * (0.15 + 0.85 * wind)
        return (value, ["height": height, "period": period, "wind": wind])
    }

    private static func surfingWindTerm(_ c: SpotConditions) -> Double {
        let knots = c.windSpeedKnots
        switch c.windRelation {
        case .offshore, .crossOffshore:
            // A light offshore is the best wind a surfer can get; a hard one
            // holds the wave up until it will not break at all.
            return Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 10, fallEnd: 22).value(knots)
        case .sideShore:
            return Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 8, fallEnd: 20).value(knots)
        case .crossOnshore, .onshore:
            // Onshore past ~12 knots tears the face apart.
            return Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 6, fallEnd: 14).value(knots)
        }
    }

    // MARK: - Kite and wing foil

    private static func windSport(
        _ c: SpotConditions,
        idealLow: Double,
        idealHigh: Double
    ) -> (Double, [String: Double]) {
        let wind = Trapezoid(
            riseStart: idealLow - 7,
            plateauStart: idealLow,
            plateauEnd: idealHigh,
            fallEnd: idealHigh + 13
        ).value(c.windSpeedKnots)

        // Side-shore lets a rider cruise out and back. Dead offshore risks being
        // blown to sea; dead onshore risks being slammed into the beach.
        let direction: Double
        switch c.windRelation {
        case .sideShore: direction = 1.0
        case .crossOnshore: direction = 0.85
        case .crossOffshore: direction = 0.5
        case .onshore: direction = 0.4
        case .offshore: direction = 0.15
        }

        // Chop is workable; big surf makes the launch hard.
        let height = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 1.2, fallEnd: 2.5)
            .value(c.waveHeightMeters)

        // No wind means no session, whatever else is true.
        let value = wind * (0.4 + 0.6 * direction) * (0.85 + 0.15 * height)
        return (value, ["wind": wind, "direction": direction, "height": height])
    }

    // MARK: - SUP

    private static func standUpPaddle(_ c: SpotConditions) -> (Double, [String: Double]) {
        // Inverted: a paddler wants exactly the sea the surfer is complaining about.
        let flatness = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 0.3, fallEnd: 0.9)
            .value(c.waveHeightMeters)
        let wind = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 6, fallEnd: 14)
            .value(c.windSpeedKnots)

        let value = flatness * (0.3 + 0.7 * wind)
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

        switch (worst, profile.sport) {
        case (.danger, .sup): return 0.05
        case (.danger, _): return 0.35
        case (.caution, .sup): return 0.4
        case (.caution, _): return 0.8
        }
    }
}
