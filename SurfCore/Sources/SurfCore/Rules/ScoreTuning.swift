import Foundation

/// Every tunable number in the Match Score, in one place.
///
/// ## Why the weights are data and the formulas are not
/// The three sport families do not share a formula. Surfing multiplies wave
/// quality by a wind term, the wind sports multiply wind by everything else, and
/// SUP rewards exactly the flat sea the surfer is complaining about. Flattening
/// those into a single uniform table would mean inventing a combinator general
/// enough to express all three, which is more machinery than the problem has.
///
/// So the *shape* of each formula stays as readable code in `MatchScoreEngine`
/// and every *number* it uses lives here. That is the split that matters in
/// practice: retuning a curve after a session at the beach is a one-line edit to
/// a literal, and no threshold is stated in more than one place.
enum ScoreTuning {
    /// Wind response keyed by where the wind sits relative to the beach.
    ///
    /// Exhaustive by construction: adding a `WindRelation` case will not compile
    /// until it has been given a curve, rather than silently picking up a default.
    struct RelationCurves: Sendable {
        let offshore: Trapezoid
        let sideShore: Trapezoid
        let onshore: Trapezoid

        subscript(relation: WindRelation) -> Trapezoid {
            switch relation {
            case .offshore, .crossOffshore: return offshore
            case .sideShore: return sideShore
            case .crossOnshore, .onshore: return onshore
            }
        }
    }

    /// A flat weight per relation, for the sports where direction scales the
    /// result rather than shaping a curve.
    struct RelationWeights: Sendable {
        let offshore: Double
        let crossOffshore: Double
        let sideShore: Double
        let crossOnshore: Double
        let onshore: Double

        subscript(relation: WindRelation) -> Double {
            switch relation {
            case .offshore: return offshore
            case .crossOffshore: return crossOffshore
            case .sideShore: return sideShore
            case .crossOnshore: return crossOnshore
            case .onshore: return onshore
            }
        }
    }

    // MARK: - Surfing

    struct Surfing: Sendable {
        /// Full marks between 0.6 m and 1.5 m at the beach, the golden range.
        let height = Trapezoid(riseStart: 0.25, plateauStart: 0.6, plateauEnd: 1.5, fallEnd: 3.0)

        /// Period is the true measure of wave quality. Under 5 s is wind slop
        /// that will not carry a board; 7 to 9 s is real energy.
        let period = Trapezoid(riseStart: 3.5, plateauStart: 7.0, plateauEnd: 12.0, fallEnd: 20.0)

        let wind = RelationCurves(
            // A light offshore is the best wind a surfer can get; a hard one
            // holds the wave up until it will not break at all.
            offshore: Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 10, fallEnd: 22),
            sideShore: Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 8, fallEnd: 20),
            // Onshore past ~12 knots tears the face apart.
            onshore: Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 6, fallEnd: 14)
        )

        /// How much of the wave-quality term survives a period of zero. Period
        /// modulates size rather than standing in for it: adding the two would
        /// let a dead flat sea with a long period score 40 out of 100.
        let periodFloor = 0.35

        /// Keeps a genuinely big, long-period day from reading as a flat zero
        /// just because it is blown out. It is still worth knowing the swell
        /// arrived.
        let windFloor = 0.15
    }

    static let surfing = Surfing()

    // MARK: - Kite and wing foil

    struct WindSport: Sendable {
        let idealLowKnots: Double
        let idealHighKnots: Double

        /// Side-shore lets a rider cruise out and back. Dead offshore risks
        /// being blown to sea; dead onshore risks being slammed into the beach.
        let direction = RelationWeights(
            offshore: 0.15, crossOffshore: 0.5, sideShore: 1.0, crossOnshore: 0.85, onshore: 0.4
        )

        /// Chop is workable; big surf makes the launch hard.
        let height = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 1.2, fallEnd: 2.5)

        let directionFloor = 0.4
        let heightFloor = 0.85

        /// How far below the ideal band a session is still on, and how far above
        /// it is over. Asymmetric because underpowered is a slow day and
        /// overpowered is a dangerous one.
        let rampBelowKnots = 7.0
        let rampAboveKnots = 13.0

        var wind: Trapezoid {
            Trapezoid(
                riseStart: idealLowKnots - rampBelowKnots,
                plateauStart: idealLowKnots,
                plateauEnd: idealHighKnots,
                fallEnd: idealHighKnots + rampAboveKnots
            )
        }
    }

    static let kitesurfing = WindSport(idealLowKnots: 15, idealHighKnots: 22)
    static let wingFoil = WindSport(idealLowKnots: 12, idealHighKnots: 22)

    // MARK: - SUP

    struct StandUpPaddle: Sendable {
        /// Inverted: a paddler wants exactly the sea the surfer is complaining about.
        let flatness = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 0.3, fallEnd: 0.9)
        let wind = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 6, fallEnd: 14)
        let windFloor = 0.3
    }

    static let sup = StandUpPaddle()

    // MARK: - Safety suppression

    /// How hard an active hazard crushes the score.
    ///
    /// A banner beside a 90 is an argument the banner loses, so for the users a
    /// hazard actually applies to, the number itself comes down. Paddlers are
    /// held to the harshest multipliers: a SUP is a sail and cannot be
    /// duck-dived under a gust.
    struct Suppression: Sendable {
        let dangerOnFloatingCraft = 0.05
        let danger = 0.35
        let cautionOnFloatingCraft = 0.4
        let caution = 0.8

        func multiplier(for severity: AlertSeverity, onFloatingCraft: Bool) -> Double {
            switch (severity, onFloatingCraft) {
            case (.danger, true): return dangerOnFloatingCraft
            case (.danger, false): return danger
            case (.caution, true): return cautionOnFloatingCraft
            case (.caution, false): return caution
            }
        }
    }

    static let suppression = Suppression()
}
