import Foundation

/// Unit conversion lives at the presentation boundary, never inside the engine.
///
/// Everything in SurfCore is SI: metres, seconds, metres per second, degrees true.
/// Knots are a display unit. The research doc's "1 knot = 1.8 km/h" is a field
/// approximation; the exact value is used here.
public enum Units {
    public static let metersPerSecondPerKnot = 0.514_444_4

    public static func knots(fromMetersPerSecond mps: Double) -> Double {
        mps / metersPerSecondPerKnot
    }

    public static func metersPerSecond(fromKnots knots: Double) -> Double {
        knots * metersPerSecondPerKnot
    }
}

/// Where the wind sits relative to the beach it is blowing at.
///
/// Derived geometrically from the spot's `shorelineNormalDegrees`, not from a
/// hardcoded "west is onshore" rule. Israel's Mediterranean coast mostly faces
/// west, but Haifa Bay faces north-west and Eilat faces south — a hardcoded
/// compass rule gets both of them wrong.
public enum WindRelation: String, Sendable, Equatable, CaseIterable {
    case offshore
    case crossOffshore
    case sideShore
    case crossOnshore
    case onshore

    /// Grooms the wave face and holds it up rather than breaking it early.
    public var isFavourableForShape: Bool {
        self == .offshore || self == .crossOffshore
    }

    /// Blows from land to sea — the drift hazard direction.
    public var blowsAwayFromShore: Bool {
        self == .offshore || self == .crossOffshore
    }
}

public enum Compass {
    /// Smallest absolute angle between two compass bearings, 0...180.
    public static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(normalize(a) - normalize(b)).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    /// Wraps any bearing into 0..<360.
    public static func normalize(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Classifies a wind against a shoreline.
    ///
    /// - Parameters:
    ///   - windFromDegrees: the direction the wind blows *from*, degrees true.
    ///   - shorelineNormalDegrees: the direction pointing from the beach out to
    ///     open sea (270 for a west-facing beach).
    ///
    /// A wind arriving *from* the open-sea direction is onshore; a wind arriving
    /// from the opposite side has crossed the land and is offshore.
    public static func windRelation(
        windFromDegrees: Double,
        shorelineNormalDegrees: Double
    ) -> WindRelation {
        let offset = angularDistance(windFromDegrees, shorelineNormalDegrees)
        switch offset {
        case ..<30: return .onshore
        case ..<60: return .crossOnshore
        case ..<120: return .sideShore
        case ..<150: return .crossOffshore
        default: return .offshore
        }
    }
}
