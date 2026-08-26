import Foundation

/// A ramp-up, plateau, ramp-down response curve.
///
/// Almost every term in the scoring model has the same shape: too little is bad,
/// too much is bad, there is a band in the middle that is ideal. Expressing that
/// once keeps the sport profiles in `ScoreTuning` declarative instead of branchy.
struct Trapezoid: Sendable, Equatable {
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
