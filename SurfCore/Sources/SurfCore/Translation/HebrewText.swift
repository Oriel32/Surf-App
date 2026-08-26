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
    /// U+2066 LEFT-TO-RIGHT ISOLATE, and U+2069 POP DIRECTIONAL ISOLATE.
    ///
    /// These replaced U+200E LEFT-TO-RIGHT MARK, which caused a real rendering
    /// bug: LRM has bidi class **L**, a strong left-to-right character. The wave
    /// line begins with its height, so the line began with an LRM — and rule P2
    /// of the bidi algorithm takes the paragraph direction from the first strong
    /// character it finds. The whole line therefore resolved as **left-to-right**
    /// and rendered inside out, with the Hebrew at one end and the number
    /// stranded at the other.
    ///
    /// Isolates fix it precisely, because P2 **skips over everything between an
    /// isolate initiator and its matching PDI**. The Hebrew decides the line's
    /// direction, and the number still renders left-to-right inside its island.
    public static let leftToRightIsolate = "\u{2066}"
    public static let popDirectionalIsolate = "\u{2069}"

    /// Hebrew geresh, U+05F3. Not an ASCII apostrophe — `מ׳` uses this, and the
    /// typography rule says so explicitly.
    public static let geresh = "\u{05F3}"

    /// Metres, abbreviated the way the product writes it: `0.8 מ׳`.
    public static func meters(_ value: Double) -> String {
        "\(ltr(String(format: "%.1f", value))) \(metersUnit)"
    }

    public static let metersUnit = "\u{05DE}\u{05F3}"

    /// Height in the reader's chosen unit.
    public static func height(_ meters: Double, unit: HeightUnit) -> String {
        let value = unit.convert(fromMeters: meters)
        return "\(ltr(String(format: "%.1f", value))) \(unit.hebrewAbbreviation)"
    }

    /// A surf range, the way every forecast quotes it: `0.6-0.8 מ׳`.
    ///
    /// The whole numeric run is isolated as one unit so the bidirectional
    /// algorithm cannot swap the two ends and render it backwards.
    public static func heightRange(_ low: Double, _ high: Double, unit: HeightUnit) -> String {
        let a = String(format: "%.1f", unit.convert(fromMeters: low))
        let b = String(format: "%.1f", unit.convert(fromMeters: high))
        return "\(ltr("\(a)-\(b)")) \(unit.hebrewAbbreviation)"
    }

    /// The same value spelled out for VoiceOver: no abbreviation, and no
    /// invisible direction marks for a screen reader to stumble over.
    public static func spokenHeight(_ meters: Double, unit: HeightUnit) -> String {
        let value = unit.convert(fromMeters: meters)
        return "\(String(format: "%.1f", value)) \(unit.spokenHebrew)"
    }

    /// Knots: `8 קשר`.
    public static func knots(_ value: Double) -> String {
        "\(ltr(String(Int(value.rounded())))) קשר"
    }

    /// A time range that must not reverse: `06:00-09:00`.
    public static func timeRange(_ start: String, _ end: String) -> String {
        ltr("\(start)-\(end)")
    }

    /// Isolates a numeric run so the bidirectional algorithm cannot reorder it,
    /// and — just as important — so the run cannot change the direction of the
    /// line it sits in.
    ///
    /// Without isolation a number carrying punctuation (a decimal point, the
    /// hyphen in a time range, a middle dot separator) gets reordered against
    /// the surrounding Hebrew and renders as `9:00-06:00`, or with the number
    /// thrown to the far end of the line away from its unit.
    ///
    /// The characters are invisible and cost nothing when the surrounding text
    /// is already left-to-right.
    public static func ltr(_ text: String) -> String {
        leftToRightIsolate + text + popDirectionalIsolate
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
