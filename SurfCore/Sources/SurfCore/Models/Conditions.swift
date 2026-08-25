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

    /// Lower bound in metres, inclusive.
    public var lowerBoundMeters: Double {
        switch self {
        case .flat: return 0
        case .ankleToKnee: return 0.20
        case .waistToChest: return 0.50
        case .shoulderToHead: return 1.00
        case .overhead: return 1.50
        case .doubleOverhead: return 2.20
        }
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
        allCases.last { height >= $0.lowerBoundMeters } ?? .flat
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
        case .choppy: return "צ'ופי"
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

    public var windSpeedKnots: Double {
        Units.knots(fromMetersPerSecond: windSpeedMPS)
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
        airTemperatureC: Double? = nil
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
    }
}
