import Foundation

/// The wind's strength band, as the research names it.
///
/// Strength and direction are separate facts and the UI says both: 15 knots
/// offshore and 15 knots onshore are the same band and opposite products. This
/// type carries only the strength half — `WindRelation` carries the direction.
public enum WindStrength: String, Sendable, Equatable, CaseIterable {
    /// 0–10 kt. Ideal for surf and SUP.
    case weak
    /// 10–15 kt. Surf degrading; ideal for a beginner windsurfer.
    case moderate
    /// 15 kt and up. Kite, windsurf and wing foil territory.
    case strong

    /// Bounds in knots, straight from the research doc's strength bands.
    /// Knots and not m/s deliberately: these thresholds are quoted, taught and
    /// argued about in knots, and translating them to SI would obscure the very
    /// numbers a local surfer needs to be able to check.
    public static let table = RuleTable<WindStrength>([
        .init(from: 0, .weak),
        .init(from: 10, .moderate),
        .init(from: 15, .strong)
    ])

    public static func strength(forKnots knots: Double) -> WindStrength {
        table.value(for: knots)
    }

    public var lowerBoundKnots: Double {
        Self.table.lowerBound(of: self) ?? 0
    }

    public var hebrew: String {
        switch self {
        case .weak: return "חלשה"
        case .moderate: return "בינונית"
        case .strong: return "חזקה"
        }
    }

    public var english: String {
        switch self {
        case .weak: return "Weak"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        }
    }
}
