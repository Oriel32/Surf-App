import Foundation

/// The thresholds behind the sea-state classification, as data rather than
/// numbers buried in a conditional.
///
/// Sea state is not a one-dimensional lookup — it depends on height, wind speed
/// *and* wind direction together — so it cannot be a `RuleTable`. What it can be
/// is a named set of tunable bounds, which is what makes the classifier readable
/// and its edges testable one at a time.
///
/// Public because it is a default argument of a public function, and default
/// argument values are inlined into callers.
public struct SeaStateRules: Sendable, Equatable {
    /// Below this the sea is flat, whatever the wind is doing.
    public let flatCeilingMeters: Double
    /// Below this wind speed the surface is glass regardless of direction.
    public let glassyCalmKnots: Double
    /// A wind coming off the land grooms the face rather than tearing it, up to here.
    public let groomedOffshoreCeilingKnots: Double
    /// Onshore wind at or above this tears the surface into chop.
    public let onshoreChopKnots: Double
    /// Any wind at or above this is chop, from any direction.
    public let universalChopKnots: Double

    /// The share of the sea's energy carried by the wind wave, at or above which
    /// the surface reads as chop however light the mean wind is.
    ///
    /// Measured, not assumed. At Bat Yam on 2026-08-29 a surfer in the water
    /// called the sea "a bit choppy and wavy" at 10:00 and unsurfable by 10:20,
    /// while this classifier said `סביר` until noon — because the mean wind never
    /// left the 0-10 kt "ideal" band. What *had* changed was the partition: the
    /// wind wave went from 11.3% of the energy at the break to 18.4% at 10:00 and
    /// 23.9% at 11:00, while the swell under it was flat to falling.
    ///
    /// 0.18 puts the first choppy hour at 10:00 and leaves 09:00 fair, which is
    /// what was reported from the water. See `calibration/bat-yam-comparison.md`.
    public let chopEnergyShare: Double

    /// Gust at or above this is chop, whatever the mean and the partition say.
    ///
    /// A second net, for the squall that is up before the sea has answered it —
    /// wave growth lags the wind by tens of minutes at these fetches, which is
    /// the likeliest reason 10:20 felt worse than the 10:00 model hour did.
    public let gustChopKnots: Double

    public init(
        flatCeilingMeters: Double = 0.1,
        glassyCalmKnots: Double = 5,
        groomedOffshoreCeilingKnots: Double = 15,
        onshoreChopKnots: Double = 12,
        universalChopKnots: Double = 20,
        chopEnergyShare: Double = 0.18,
        gustChopKnots: Double = 18
    ) {
        self.flatCeilingMeters = flatCeilingMeters
        self.glassyCalmKnots = glassyCalmKnots
        self.groomedOffshoreCeilingKnots = groomedOffshoreCeilingKnots
        self.onshoreChopKnots = onshoreChopKnots
        self.universalChopKnots = universalChopKnots
        self.chopEnergyShare = chopEnergyShare
        self.gustChopKnots = gustChopKnots
    }

    public static let standard = SeaStateRules()
}
