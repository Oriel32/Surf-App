import Foundation

/// The named factors a Match Score is built from.
///
/// `MatchScoreEngine` emits these as `[String: Double]` on `MatchScore`, which
/// is the right shape for an engine that multiplies them and does not care what
/// they are called. It is the wrong shape for a screen: a dictionary has no
/// order, and a display that iterates it puts the same five factors in a
/// different sequence on every redraw.
///
/// So the keys get typed here, at the presentation boundary, rather than in the
/// engine. That buys the ordering and the Hebrew without touching the scoring
/// code or its tests.
///
/// Every value is a **normalised 0-1 factor**, not a weight and not a
/// contribution. 1.0 means "this aspect is as good as it gets"; the score is
/// their product, so the smallest factor is the one holding the day back.
public enum ScoreComponent: String, Sendable, Equatable, CaseIterable {
    // Surfing.
    case energy
    case size
    case shape
    case wind
    case gust
    // Kite and wing foil.
    case direction
    case height
    // SUP.
    case flatness

    public var hebrew: String {
        switch self {
        case .energy: return "אנרגיה"
        case .size: return "גודל"
        // Period wearing its other hat. Inside `energy` the period is power;
        // here it is whether that power arrives as a wave that stands up and
        // peels, which is what a surfer means by shape.
        case .shape: return "צורת הגל"
        case .wind: return "רוח"
        case .gust: return "יציבות הרוח"
        case .direction: return "כיוון הרוח"
        case .height: return "גובה"
        case .flatness: return "שקט"
        }
    }

    /// The sentence naming this factor as the one holding the score back.
    ///
    /// Written per factor rather than assembled from the noun, because Hebrew
    /// will not take a single template across all eight of these without reading
    /// like a machine translated it.
    public var limitingSentenceHebrew: String {
        switch self {
        case .energy: return "אין מספיק אנרגיה בים — זה מה שמעכב."
        case .size: return "הגלים קטנים מדי — זה מה שמעכב."
        case .shape: return "המחזור קצר והגלים לא מסתדרים — זה מה שמעכב."
        case .wind: return "הרוח היא מה שמעכב."
        case .gust: return "הרוח משתנה ומשברת את פני המים — זה מה שמעכב."
        case .direction: return "כיוון הרוח הוא מה שמעכב."
        case .height: return "גובה הגלים הוא מה שמעכב."
        case .flatness: return "הים גלי מדי לסאפ — זה מה שמעכב."
        }
    }

    /// Display order per sport, so the card reads the same way every time.
    ///
    /// Ordered the way the engine reasons: what the sea is doing first, then
    /// what the wind is doing to it. For the wind sports that order inverts,
    /// because the wind is the session and the sea is a condition on it.
    public static func order(for sport: Sport) -> [ScoreComponent] {
        switch sport {
        case .surfing: return [.energy, .size, .shape, .wind, .gust]
        case .kitesurfing, .wingFoil: return [.wind, .direction, .height]
        case .sup: return [.flatness, .wind]
        }
    }
}
