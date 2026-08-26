import Foundation

/// The score's verbal band. The Match Score is coloured by band, and per the
/// colour rule a colour never carries meaning alone, so every band owns a word
/// as well as a token.
public enum ScoreBand: String, Sendable, Equatable, CaseIterable {
    case poor
    case fair
    case good
    case excellent

    /// The `fair` boundary is not a free choice: it is the same threshold
    /// `WindowFinder` uses to decide an hour is worth driving to, and the two
    /// must not be able to disagree. A screen that paints an hour "fair" while
    /// the window finder refuses to recommend it is telling the user two things.
    ///
    /// The 60 and 80 boundaries are a working default; the research names no
    /// score bands. Confirm with a local surfer before shipping.
    public static let table = RuleTable<ScoreBand>([
        .init(from: 0, .poor),
        .init(from: Double(WindowFinder.usableScore), .fair),
        .init(from: 60, .good),
        .init(from: 80, .excellent)
    ])

    public static func band(forScore score: Int) -> ScoreBand {
        table.value(for: Double(score))
    }

    public var hebrew: String {
        switch self {
        case .poor: return "חלש"
        case .fair: return "סביר"
        case .good: return "טוב"
        case .excellent: return "מצוין"
        }
    }

    public var english: String {
        switch self {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}
