import Foundation

/// The eight-point compass, as a word.
///
/// A bearing in degrees is engine data. `259°` on a screen is noise nobody reads,
/// while "מערבית" is the fact the surfer acts on.
public enum CompassPoint: String, Sendable, Equatable, CaseIterable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    /// Sector boundaries at the 22.5-degree midpoints.
    ///
    /// The wrap is the interesting row: north owns both the bottom of the circle
    /// and everything from 337.5 up, so it appears twice and the table stays a
    /// plain ascending lookup instead of needing special-case arithmetic.
    public static let table = RuleTable<CompassPoint>([
        .init(from: 0, .north),
        .init(from: 22.5, .northEast),
        .init(from: 67.5, .east),
        .init(from: 112.5, .southEast),
        .init(from: 157.5, .south),
        .init(from: 202.5, .southWest),
        .init(from: 247.5, .west),
        .init(from: 292.5, .northWest),
        .init(from: 337.5, .north)
    ])

    public static func point(forDegrees degrees: Double) -> CompassPoint {
        table.value(for: Compass.normalize(degrees))
    }

    /// The adjective form, which is how a wind is named in Hebrew:
    /// "רוח מזרחית", an easterly wind.
    public var hebrewAdjective: String {
        switch self {
        case .north: return "צפונית"
        case .northEast: return "צפון-מזרחית"
        case .east: return "מזרחית"
        case .southEast: return "דרום-מזרחית"
        case .south: return "דרומית"
        case .southWest: return "דרום-מערבית"
        case .west: return "מערבית"
        case .northWest: return "צפון-מערבית"
        }
    }

    public var english: String {
        switch self {
        case .north: return "N"
        case .northEast: return "NE"
        case .east: return "E"
        case .southEast: return "SE"
        case .south: return "S"
        case .southWest: return "SW"
        case .west: return "W"
        case .northWest: return "NW"
        }
    }
}

public extension WindRelation {
    /// Where the wind is coming from, in the terms that change behaviour.
    ///
    /// Deliberately not a transliteration of the English. A surfer deciding
    /// whether to paddle out cares that the wind is coming off the land, which
    /// is what "מהיבשה" says directly.
    var hebrew: String {
        switch self {
        case .offshore: return "מהיבשה"
        case .crossOffshore: return "אלכסונית מהיבשה"
        case .sideShore: return "צדדית"
        case .crossOnshore: return "אלכסונית מהים"
        case .onshore: return "מהים"
        }
    }

    var english: String {
        switch self {
        case .offshore: return "Offshore"
        case .crossOffshore: return "Cross-offshore"
        case .sideShore: return "Side-shore"
        case .crossOnshore: return "Cross-onshore"
        case .onshore: return "Onshore"
        }
    }
}

/// Hebrew number and unit formatting.
///
/// Hebrew is the primary locale, so every number in the app is a numeric run
/// inside a right-to-left paragraph. Two things go wrong there by default and
/// both are handled here rather than in each view.
public enum HebrewText {
    /// U+200E LEFT-TO-RIGHT MARK.
    public static let leftToRightMark = "\u{200E}"

    /// Hebrew geresh, U+05F3. Not an ASCII apostrophe — `מ׳` uses this, and the
    /// typography rule says so explicitly.
    public static let geresh = "\u{05F3}"

    /// Metres, abbreviated the way the product writes it: `0.8 מ׳`.
    public static func meters(_ value: Double) -> String {
        "\(ltr(String(format: "%.1f", value))) \(metersUnit)"
    }

    public static let metersUnit = "\u{05DE}\u{05F3}"

    /// Knots: `8 קשר`.
    public static func knots(_ value: Double) -> String {
        "\(ltr(String(Int(value.rounded())))) קשר"
    }

    /// A time range that must not reverse: `06:00-09:00`.
    public static func timeRange(_ start: String, _ end: String) -> String {
        ltr("\(start)-\(end)")
    }

    /// Isolates a numeric run so the bidirectional algorithm cannot reorder it.
    ///
    /// Without this, a number carrying punctuation — a decimal point, a hyphen
    /// in a time range, a middle dot separator — can be reordered against the
    /// surrounding Hebrew and render as `9:00-06:00` or with the decimal in the
    /// wrong place. The marks are invisible and cost nothing when the text is
    /// laid out left-to-right.
    public static func ltr(_ text: String) -> String {
        leftToRightMark + text + leftToRightMark
    }

    /// The same value spelled out for VoiceOver.
    ///
    /// VoiceOver reads meaning, not layout, so the screen reader gets `מטר` and
    /// no invisible direction marks — an abbreviation with a geresh in it is
    /// read as a letter, not as a unit.
    public static func spokenMeters(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) מטר"
    }

    public static func spokenKnots(_ value: Double) -> String {
        "\(Int(value.rounded())) קשר"
    }
}
