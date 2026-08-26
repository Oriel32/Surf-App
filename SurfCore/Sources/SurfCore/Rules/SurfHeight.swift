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
    /// **Open question, same status as the `overhead` band and the score
    /// boundaries.** Keyed to the sets on the reasoning that "waist to chest"
    /// describes the wave a surfer stood next to, and nobody names a beach day
    /// after its statistical mean. Confirm with a local surfer; changing it is
    /// one line.
    public var bandDefiningMeters: Double {
        setMeters
    }
}
