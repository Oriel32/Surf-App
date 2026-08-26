import Foundation

/// Wave height expressed the way surfers actually measure it — against the body
/// standing on the board, not against a ruler.
///
/// Bands are contiguous by construction. The research doc names centres
/// (0.20–0.40, 0.50–0.90, 1.00–1.50) and leaves gaps between them; a band table
/// with holes in it silently drops real conditions on the floor, so the
/// boundaries below close the gaps at the midpoints.
public enum WaveBand: String, Sendable, Equatable, CaseIterable {
    case flat
    case ankleToKnee
    case waistToChest
    case shoulderToHead
    case overhead
    case doubleOverhead

    /// The band boundaries, as one readable table a local surfer can check
    /// line by line. `RuleTable` rejects a non-ascending edit outright, so the
    /// bands cannot be left overlapping or out of order by a later change.
    public static let table = RuleTable<WaveBand>([
        .init(from: 0, .flat),
        .init(from: 0.20, .ankleToKnee),
        .init(from: 0.50, .waistToChest),
        .init(from: 1.00, .shoulderToHead),
        .init(from: 1.50, .overhead),
        .init(from: 2.20, .doubleOverhead)
    ])

    /// Lower bound in metres, inclusive. Read back from the table, so a
    /// threshold is never stated in two places that can drift apart.
    public var lowerBoundMeters: Double {
        Self.table.lowerBound(of: self) ?? 0
    }

    public var hebrew: String {
        switch self {
        case .flat: return "פלטה"
        case .ankleToKnee: return "קרסול עד ברך"
        case .waistToChest: return "מותן עד חזה"
        case .shoulderToHead: return "כתף עד ראש"
        // Working default: the research jumps straight from 1.5 m to "double
        // overhead", leaving this band unnamed. Confirm with a local surfer.
        case .overhead: return "ראש"
        case .doubleOverhead: return "פעמיים ראש ומעלה"
        }
    }

    public var english: String {
        switch self {
        case .flat: return "Flat"
        case .ankleToKnee: return "Ankle to knee"
        case .waistToChest: return "Waist to chest"
        case .shoulderToHead: return "Shoulder to head"
        case .overhead: return "Overhead"
        case .doubleOverhead: return "Double overhead+"
        }
    }

    public static func band(forHeightMeters height: Double) -> WaveBand {
        table.value(for: height)
    }
}

/// The texture of the water surface — what the wind is doing to the face.
public enum SeaState: String, Sendable, Equatable, CaseIterable {
    case flat
    case glassy
    case fair
    case choppy

    public var hebrew: String {
        switch self {
        case .flat: return "פלטה"
        case .glassy: return "גלאסי"
        // Not from the research, which names only flat/glassy/choppy. A binary
        // glassy-or-choppy misdescribes most real days, so this middle state
        // uses plain Hebrew rather than invented slang. Confirm the wording.
        case .fair: return "סביר"
        case .choppy: return "צ׳ופי"
        }
    }

    public var english: String {
        switch self {
        case .flat: return "Flat"
        case .glassy: return "Glassy"
        case .fair: return "Fair"
        case .choppy: return "Choppy"
        }
    }
}

/// The transformed, spot-specific, presentable conditions.
///
/// This — not `RawMarineSample` — is what the UI renders.
public struct SpotConditions: Sendable, Equatable {
    public let timestamp: Date
    public let spotID: String

    /// Breaking wave height at this spot, metres, after shoaling, refraction,
    /// sheltering and the breaking cap.
    public let waveHeightMeters: Double
    public let periodSeconds: Double
    public let band: WaveBand
    public let seaState: SeaState

    public let windSpeedMPS: Double
    public let windDirectionDegrees: Double
    public let windRelation: WindRelation

    /// The untransformed open-sea height, kept so the detail view can show its
    /// work. Displaying both is what proves the app transformed the data rather
    /// than reprinting a model.
    public let openSeaHeightMeters: Double

    /// True when values were synthesised from local wind rather than taken from
    /// a wave model — the Gulf of Eilat case. The UI must label these.
    public let isSynthetic: Bool

    public let seaSurfaceTemperatureC: Double?
    public let airTemperatureC: Double?

    /// Sea level relative to mean, metres. Low in the hierarchy on purpose:
    /// the Mediterranean tidal range is a few dozen centimetres, so this
    /// informs where a wave breaks rather than whether to go.
    public let seaLevelMeters: Double?

    public var windSpeedKnots: Double {
        Units.knots(fromMetersPerSecond: windSpeedMPS)
    }

    /// The wind's strength band. Direction stays separate in `windRelation`:
    /// 15 knots offshore and 15 knots onshore are the same band and opposite
    /// products, and collapsing them into one adjective loses the product.
    public var windStrength: WindStrength {
        WindStrength.strength(forKnots: windSpeedKnots)
    }

    public init(
        timestamp: Date,
        spotID: String,
        waveHeightMeters: Double,
        periodSeconds: Double,
        band: WaveBand,
        seaState: SeaState,
        windSpeedMPS: Double,
        windDirectionDegrees: Double,
        windRelation: WindRelation,
        openSeaHeightMeters: Double,
        isSynthetic: Bool,
        seaSurfaceTemperatureC: Double? = nil,
        airTemperatureC: Double? = nil,
        seaLevelMeters: Double? = nil
    ) {
        self.timestamp = timestamp
        self.spotID = spotID
        self.waveHeightMeters = waveHeightMeters
        self.periodSeconds = periodSeconds
        self.band = band
        self.seaState = seaState
        self.windSpeedMPS = windSpeedMPS
        self.windDirectionDegrees = windDirectionDegrees
        self.windRelation = windRelation
        self.openSeaHeightMeters = openSeaHeightMeters
        self.isSynthetic = isSynthetic
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.airTemperatureC = airTemperatureC
        self.seaLevelMeters = seaLevelMeters
    }
}
