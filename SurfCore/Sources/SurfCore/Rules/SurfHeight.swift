import Foundation

/// How a measured sea becomes the number a surfer would say out loud.
///
/// ## Why a range and not one number
/// `SpotConditions.waveHeightMeters` is a *significant* breaking height: the
/// mean of the highest third. It is a real statistic, and it is not the wave
/// anyone talks about. Surfers name the **sets** — the ones worth paddling for —
/// and in a Rayleigh-distributed sea those run consistently above the
/// significant height.
///
/// This is why Surfline quotes "2–3 ft" rather than a single figure, and why
/// showing only the significant height reads smaller than every app a user
/// might cross-check against, for exactly the same sea.
///
/// The multipliers below are Rayleigh wave statistics, not tuning constants:
/// they follow from the distribution and are the same numbers in any textbook.
public enum WaveStatistics {
    /// H(1/10) / H(1/3). The Rayleigh value is 1.27; 1.25 is the commonly
    /// quoted rounding.
    public static let oneInTen = 1.27

    /// H(1/100) / H(1/3). The rare outside set — used for the safety copy, not
    /// for the headline number.
    public static let oneInHundred = 1.67
}

/// The surf, as a range from the ordinary waves to the sets.
public struct SurfRange: Sendable, Equatable {
    /// Significant breaking height — the physical value the engine computed.
    public let significantMeters: Double
    /// The 1-in-10 wave. What a surfer means by "it was chest high".
    public let setMeters: Double

    public init(significantMeters: Double) {
        self.significantMeters = significantMeters
        self.setMeters = significantMeters * WaveStatistics.oneInTen
    }

    /// The largest wave a session should be planned around, for safety copy.
    public var outsideSetMeters: Double {
        significantMeters * WaveStatistics.oneInHundred
    }

    /// The height the slang band is chosen from.
    ///
    /// Keyed to the **significant height**, which is the low end of the range
    /// the app displays, so the word and the number a user reads on one line
    /// describe the same wave.
    ///
    /// This was previously keyed to the sets, on the reasoning that nobody names
    /// a beach day after its statistical mean. That reasoning is sound and it
    /// still produced a contradiction on screen: `0.48 m` printed beside
    /// `מותן עד חזה`, because the band had been chosen from 0.61 m. Measured
    /// against GoSurf on 2026-08-27 at Bat Yam — same sea, same hour — they
    /// called it `קרסול` and we called it waist-to-chest, two bands apart.
    /// See `calibration/bat-yam-comparison.md`.
    ///
    /// The sets did not disappear: they are the top of the displayed range.
    public var bandDefiningMeters: Double {
        significantMeters
    }
}
