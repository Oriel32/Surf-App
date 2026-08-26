import Foundation

/// A semantic colour, named for what it means rather than what it looks like.
///
/// SurfCore never imports SwiftUI — the moment it does, the whole build-and-test
/// off-Mac workflow dies — so the translation layer emits tokens and the app
/// target maps them to actual colours. That also keeps the palette a single
/// decision made once in the view layer rather than a literal scattered through
/// the engine.
///
/// Per the colour rule, a token never travels alone: every value that carries one
/// also carries its word, so nothing is lost in greyscale or to a red-green
/// colourblind reader.
public enum ColorToken: String, Sendable, Equatable, CaseIterable {
    /// Grey. Nothing happening, or nothing worth emphasising.
    case neutral
    /// The glassy blue. The hero state, and rare by design — spending it on
    /// anything ordinary is what would stop it landing when it is real.
    case hero
    /// A good day, without the hero moment.
    case positive
    /// Orange. Degraded conditions, or a hazard that is not yet dangerous.
    case caution
    /// Red. An active hazard.
    case danger
}

public extension SeaState {
    /// Straight from the research doc's sea-state table.
    var colorToken: ColorToken {
        switch self {
        case .flat: return .neutral
        case .glassy: return .hero
        case .fair: return .positive
        case .choppy: return .caution
        }
    }
}

public extension ScoreBand {
    /// `poor` and `fair` share the neutral token on purpose. The difference
    /// between a 30 and a 50 is not worth a colour, and the band word carries it
    /// either way; reserving emphasis for the days actually worth driving to is
    /// what keeps the emphasis meaningful.
    var colorToken: ColorToken {
        switch self {
        case .poor, .fair: return .neutral
        case .good: return .positive
        case .excellent: return .hero
        }
    }
}

public extension AlertSeverity {
    var colorToken: ColorToken {
        switch self {
        case .caution: return .caution
        case .danger: return .danger
        }
    }
}
