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
        /// Whether the sea is rideable at all - a **gate**, not a scale.
        ///
        /// This deliberately sits flat across the whole usable range and only
        /// falls away at the edges: nothing to catch below roughly a third of a
        /// metre, and beyond about two metres a beach break stops being a
        /// session for most people.
        ///
        /// It used to be the research's 0.6-1.5 m golden range, which was wrong
        /// *once `energy` existed*: power already goes as `H^2`, so a ramp here
        /// across the same heights charged a small sea twice for being small and
        /// dragged every ordinary day toward zero. Size and power are one fact,
        /// and energy is the one that measures it.
        let height = Trapezoid(riseStart: 0.15, plateauStart: 0.35, plateauEnd: 2.0, fallEnd: 3.5)

        /// Period is the true measure of wave quality. Under 5 s is wind slop
        /// that will not carry a board; 7 to 9 s is real energy.
        ///
        /// Reported for transparency but no longer a scoring term of its own -
        /// `energy` below combines it with height the way the physics does.
        ///
        /// **Known miscalibration, deliberately not yet changed.** This plateau
        /// is an ocean band. The measured median peak period on this coast is
        /// 6.3 s, so a normal good local day can never reach it. Moving it is a
        /// threshold change, and thresholds here come from data or from a local
        /// surfer, never from a hunch - so it waits for the calibration log.
        let period = Trapezoid(riseStart: 3.5, plateauStart: 7.0, plateauEnd: 12.0, fallEnd: 20.0)

        /// Wave power in kW/m, and the term that actually drives the score.
        ///
        /// Height and period are not independent: power goes as `H^2 T`, which
        /// is why Surfline and Magicseaweed both lead with energy rather than
        /// height. Scoring them as two separate trapezoids and multiplying, as
        /// this did before, counts height once and period once where the
        /// physics counts height twice.
        ///
        /// The bounds are read off the research's own golden range rather than
        /// invented: 0.6 m at 7 s gives 1.25 kW/m and 1.5 m at 9 s gives 10.1,
        /// so those are the plateau. Below 0.4 there is nothing to ride. The
        /// upper fall is loose on purpose - `height` is what rules out a sea
        /// that is simply too big, and it should not be ruled out twice.
        /// **Deliberately left where it was.** Raising the plateau was the first
        /// answer to "the scores read too high", and measurement rejected it: at
        /// a plateau of 4.0 a glassy 0.9 m at 8 s morning — an unambiguously
        /// good day, and one the research puts squarely inside the golden range
        /// that earns full height marks — dropped to 79.
        ///
        /// The complaint was never that good days score well. It was that a
        /// gusty day scored 80 and that a peak of 99 landed at 20:00, after
        /// sunset. Those are the daylight filter and the gust term, and neither
        /// needs this curve moved.
        /// Calibrated against two fixed points rather than guessed.
        ///
        /// **The top, 2.4 kW/m**, is 0.9 m at 6.3 s — a genuinely good local day
        /// at the period this coast actually runs. It was 3.2, which is the same
        /// 0.9 m at *8 s*: a period the Mediterranean almost never sees, so a
        /// good day here could never reach full energy credit and a clean 1 m
        /// morning capped out around 85% of the term.
        ///
        /// Lowering it further is the trap. At the old plateau of 1.25 a 0.6 m,
        /// 7.7 s, 7-knot sideshore morning scored 100, and a pleasant small
        /// morning is not a hundred-out-of-hundred day — that saturation was the
        /// run of 99s. At 2.4 the same morning carries 1.26 kW/m and reaches
        /// about half the term, which is what it deserves.
        ///
        /// **The rise, 0.15**, removes a cliff: at 0.4 a genuinely flat day
        /// (0.26-0.34 m at 5 s, measured) scored a flat zero every hour, which
        /// reads as broken data rather than a small sea and draws an empty bar
        /// on the week chart.
        let energy = Trapezoid(riseStart: 0.15, plateauStart: 2.4, plateauEnd: 12.0, fallEnd: 45.0)

        /// How ragged the wind is — gust divided by mean, not gust in knots.
        ///
        /// This is the term that was missing when a day got called "very windy"
        /// and still scored 80. Measured here, gusts run 1.7x to 3.2x the mean
        /// while the mean itself stays inside every light-wind band the score
        /// has, so nothing in the model could see the thing being complained
        /// about.
        ///
        /// The bounds come from the coast, not from a hunch. A first attempt put
        /// the plateau at 1.4x and measurement threw it out: the *median* gust
        /// ratio here is 1.85-2.04 on every day of an ordinary week, so a 1.4
        /// plateau charged every hour the same ~18% and discriminated nothing.
        /// A penalty everything pays is not a penalty.
        ///
        /// Flat to 1.9x, which is this coast's normal, so a typical day pays
        /// nothing. Zero by 3.4x, just past the 3.1-3.8 peaks observed on the
        /// days that actually get called windy.
        let gust = Trapezoid(riseStart: -1, plateauStart: 0, plateauEnd: 1.9, fallEnd: 3.4)

        /// Gustiness degrades a session; it does not cancel one. Even the
        /// raggedest wind leaves over half the score standing.
        let gustFloor = 0.55

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
        ///
        /// Lowered from 0.15: a fully blown-out day was keeping a seventh of its
        /// wave quality, which propped up the bottom of the range and made
        /// ruined days look merely mediocre. 5% still says "the swell is there"
        /// without pretending the day is surfable.
        let windFloor = 0.05
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
