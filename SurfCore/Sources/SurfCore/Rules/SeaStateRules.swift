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

    public init(
        flatCeilingMeters: Double = 0.1,
        glassyCalmKnots: Double = 5,
        groomedOffshoreCeilingKnots: Double = 15,
        onshoreChopKnots: Double = 12,
        universalChopKnots: Double = 20
    ) {
        self.flatCeilingMeters = flatCeilingMeters
        self.glassyCalmKnots = glassyCalmKnots
        self.groomedOffshoreCeilingKnots = groomedOffshoreCeilingKnots
        self.onshoreChopKnots = onshoreChopKnots
        self.universalChopKnots = universalChopKnots
    }

    public static let standard = SeaStateRules()
}
