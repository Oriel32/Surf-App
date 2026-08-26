import Foundation

/// What to wear, derived from water temperature.
///
/// The research names four categories — swimsuit, lycra, thin summer wetsuit,
/// thick winter wetsuit — and calls the decision "critical information for
/// planning required equipment", but it gives **no temperatures**. So the
/// categories below are the doc's; the boundaries are a working default and
/// carry the same health warning as the `overhead` slang band and the score
/// bands: confirm with a local surfer before shipping.
///
/// They are set for the Israeli Mediterranean, which runs roughly 16 °C in
/// February to 30 °C in August, so the whole ladder is exercised across a year.
public enum Wetsuit: String, Sendable, Equatable, CaseIterable {
    case winterSuit
    case summerSuit
    case lycra
    case swimsuit

    /// Working default. Not from the research — see the type's note.
    public static let table = RuleTable<Wetsuit>([
        .init(from: -5, .winterSuit),
        .init(from: 19, .summerSuit),
        .init(from: 23, .lycra),
        .init(from: 26, .swimsuit)
    ])

    public static func recommendation(forWaterTemperatureC celsius: Double) -> Wetsuit {
        table.value(for: celsius)
    }

    public var hebrew: String {
        switch self {
        case .winterSuit: return "חליפה מלאה"
        case .summerSuit: return "חליפה קצרה"
        case .lycra: return "לייקרה"
        case .swimsuit: return "בגד ים"
        }
    }

    public var english: String {
        switch self {
        case .winterSuit: return "Full wetsuit"
        case .summerSuit: return "Shorty wetsuit"
        case .lycra: return "Lycra"
        case .swimsuit: return "Swimsuit"
        }
    }

    /// SF Symbol name. Chosen from the system set rather than drawn: a custom
    /// glyph would have to be authored across 27 weight/scale variants to
    /// behave like a system one, and none of these needs that.
    public var symbolName: String {
        switch self {
        case .winterSuit: return "snowflake"
        case .summerSuit: return "thermometer.medium"
        case .lycra: return "tshirt"
        case .swimsuit: return "sun.max"
        }
    }
}

/// Wave height display unit.
///
/// Knots are deliberately absent: the research is explicit that "wind strength
/// in marine systems is always measured in knots", so wind has no alternative
/// unit to offer. Height is the only genuine preference here.
public enum HeightUnit: String, Sendable, Codable, Equatable, CaseIterable {
    case meters
    case feet

    public static let feetPerMeter = 3.280_839_895

    public func convert(fromMeters meters: Double) -> Double {
        self == .meters ? meters : meters * Self.feetPerMeter
    }

    public var hebrewAbbreviation: String {
        // Geresh, not an ASCII apostrophe.
        self == .meters ? "\u{05DE}\u{05F3}" : "רגל"
    }

    public var spokenHebrew: String {
        self == .meters ? "מטר" : "רגל"
    }
}
