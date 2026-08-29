import Foundation

/// The water moving *along* the beach, rather than the waves moving toward it.
///
/// ## Why this exists
/// On 2026-08-29 at Bat Yam a surfer came out of the water at 10:20 and named
/// current twice — "a little bit of current" at 10:00, "a lot of current and
/// disorganized waves" twenty minutes later. It was the thing that ended the
/// session, and the engine had no representation of it at all: the only
/// water-motion concept in the codebase was the offshore-**wind** drift alert,
/// which correctly stayed silent because the wind that morning was onshore.
///
/// ## What it is not
/// This is **not** the offshore drift hazard, and it must never be presented as
/// one. That alert is about wind blowing a beginner out to sea past the wind
/// shadow, it is non-dismissable, and it owns the top of the Home screen alone.
/// A longshore current pushes a surfer *down the beach*, which is a nuisance and
/// a fitness problem rather than the specific life-threatening illusion the
/// safety banner exists for. Diluting that banner with a second, more frequent
/// alert is how people learn to ignore it.
///
/// ## Confidence
/// **Provisional.** The mechanism is textbook and every input was already in the
/// transform, but one morning cannot validate a magnitude — and that particular
/// morning is an awkward one to calibrate against, because the two trains were
/// opposed and partly cancelling. Treat the sign and the trend as meaningful and
/// the absolute number as an estimate until the calibration log has more
/// sessions in it. This is why it informs the score only for the users a
/// mistake would matter to, and does not raise an alert for anyone.
public enum LongshoreCurrent {
    /// Longuet-Higgins' coefficient for peak longshore velocity in the surf zone,
    /// `V = 1.17·√(g·H_b)·sin θ_b·cos θ_b`. The standard value for a plane beach
    /// with the usual mixing assumptions.
    public static let waveCoefficient = 1.17

    /// Wind-driven surface drift as a fraction of wind speed. The classic 3% rule
    /// — only the alongshore component of it contributes here, since the onshore
    /// part piles water up rather than moving it along the beach.
    public static let windDriftFraction = 0.03

    /// Signed longshore current at the break, m/s.
    ///
    /// Positive flows toward `shorelineNormalDegrees + 90`, negative toward
    /// `shorelineNormalDegrees - 90`. At a west-facing beach that is northward
    /// and southward respectively.
    ///
    /// The sign is the point as much as the magnitude: two trains on opposite
    /// sides of the normal partly cancel in this sum while making the water more
    /// confused, not less, which is why `SpotConditions.isCrossSea` is carried
    /// separately rather than being inferred from a small number here.
    public static func estimate(
        trains: [(heightMeters: Double, periodSeconds: Double, directionDegrees: Double)],
        depthMeters depth: Double,
        windSpeedMPS: Double,
        windDirectionDegrees: Double,
        shorelineNormalDegrees normal: Double
    ) -> Double {
        var total = 0.0

        for train in trains where train.heightMeters > 0 {
            let offset = Compass.signedOffset(train.directionDegrees, from: normal)
            // Behind the shoreline: the train never reaches this beach, so it
            // drives nothing. Same half-plane test the transform uses.
            guard abs(offset) < 90 else { continue }

            guard let theta = WaveTransform.refractedAngleRadians(
                periodSeconds: train.periodSeconds,
                depthMeters: depth,
                incidentAngleDegrees: offset
            ) else { continue }

            let speed = waveCoefficient
                * (WaveTransform.g * train.heightMeters).squareRoot()
                * sin(theta) * cos(theta)

            // A train arriving from clockwise of the normal drives the water
            // anticlockwise along the beach, and vice versa. At Bat Yam that is
            // a north-west swell pushing south and a south-west chop pushing
            // north — the two that were fighting each other.
            total += offset > 0 ? -speed : speed
        }

        // The wind drags the surface along with it. Only the alongshore part:
        // a wind blowing straight at the beach has no component to contribute.
        let towardPositive = (windDirectionDegrees + 90 - normal) * .pi / 180
        total += windDriftFraction * windSpeedMPS * cos(towardPositive)

        return total
    }
}
