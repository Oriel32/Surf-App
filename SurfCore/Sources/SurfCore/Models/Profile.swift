import Foundation

/// What the user is going to the beach to do. Changes the meaning of every
/// number in the app: 18 knots ruins a surf session and makes a kite session.
public enum Sport: String, Sendable, Codable, Equatable, CaseIterable {
    case surfing
    case kitesurfing
    case wingFoil
    case sup

    public var hebrew: String {
        switch self {
        case .surfing: return "גלישה"
        case .kitesurfing: return "קייטסרפינג"
        case .wingFoil: return "ווינג פויל"
        case .sup: return "סאפ"
        }
    }
}

/// Not cosmetic. The same glassy offshore morning is a career-best session for
/// an advanced surfer and a drowning risk for a beginner on a SUP, so skill
/// level modulates both the score and the safety threshold.
///
/// Defaults to `.beginner`: the failure mode of over-warning is annoyance, the
/// failure mode of under-warning is a rescue.
public enum SkillLevel: String, Sendable, Codable, Equatable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    public var hebrew: String {
        switch self {
        case .beginner: return "מתחיל"
        case .intermediate: return "בינוני"
        case .advanced: return "מנוסה"
        }
    }

    public var english: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    /// Offshore wind speed, in knots, at which this user gets warned.
    public var offshoreWarningThresholdKnots: Double {
        switch self {
        case .beginner: return 8
        case .intermediate: return 10
        case .advanced: return 14
        }
    }

    /// Breaking height, in metres, at which this user gets a large-surf warning.
    ///
    /// **Stated in metres on purpose.** This used to be expressed as a
    /// `WaveBand` case, which meant re-cutting the band table silently moved
    /// three safety triggers with it. A vocabulary change must never be able to
    /// decide when somebody is warned about the size of the sea.
    ///
    /// The values match the bands they replaced to within 5 cm, and every one
    /// warns at or slightly *before* the height that used to trigger it:
    /// beginner 1.00 → 0.95 (`מותן`), intermediate 1.50 → 1.45 (`כתף`),
    /// advanced 2.20 → 2.20 (`פעמיים ראש`).
    public var largeSurfWarningThresholdMeters: Double {
        switch self {
        case .beginner: return 0.95
        case .intermediate: return 1.45
        case .advanced: return 2.20
        }
    }
}

public struct UserProfile: Sendable, Codable, Equatable {
    public var sport: Sport
    public var skill: SkillLevel

    public init(sport: Sport = .surfing, skill: SkillLevel = .beginner) {
        self.sport = sport
        self.skill = skill
    }
}

public enum AlertSeverity: String, Sendable, Equatable, Comparable {
    case caution
    case danger

    private var rank: Int { self == .caution ? 0 : 1 }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A hazard that outranks the score in the layout, always.
public struct SafetyAlert: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case offshoreDrift
        case largeSurf
    }

    public let kind: Kind
    public let severity: AlertSeverity
    public let hebrewTitle: String
    public let hebrewBody: String

    public init(kind: Kind, severity: AlertSeverity, hebrewTitle: String, hebrewBody: String) {
        self.kind = kind
        self.severity = severity
        self.hebrewTitle = hebrewTitle
        self.hebrewBody = hebrewBody
    }
}

/// 0–100 for the selected sport, plus the reasoning behind it.
///
/// `components` exists so the detail view can explain a score instead of
/// asserting it — "82" is not useful, "82, held back by the period" is.
public struct MatchScore: Sendable, Equatable {
    public let value: Int
    public let sport: Sport
    public let components: [String: Double]

    public init(value: Int, sport: Sport, components: [String: Double] = [:]) {
        self.value = value
        self.sport = sport
        self.components = components
    }
}

/// Everything the UI needs for one hour at one spot, already decided.
public struct HourlyForecast: Sendable, Equatable {
    public let conditions: SpotConditions
    public let score: MatchScore
    public let alerts: [SafetyAlert]

    public init(conditions: SpotConditions, score: MatchScore, alerts: [SafetyAlert]) {
        self.conditions = conditions
        self.score = score
        self.alerts = alerts
    }
}
