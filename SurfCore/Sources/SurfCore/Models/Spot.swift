import Foundation

/// Which body of water a spot sits in. This is not decoration — global wave
/// models do not resolve the Gulf of Eilat, and their output there is
/// meaningless, so the basin selects an entirely different code path.
public enum Basin: String, Sendable, Codable, Equatable {
    case mediterranean
    case gulfOfEilat
}

/// A surfable location, with the geometry needed to turn open-sea model output
/// into what actually breaks here.
///
/// Loaded from `Resources/spots.json` — data, not Swift. Adding a beach must
/// never require a recompile.
public struct Spot: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let nameHebrew: String
    public let nameEnglish: String
    public let latitude: Double
    public let longitude: Double
    public let basin: Basin

    /// Fraction of open-sea wave energy that survives the approach to this
    /// beach: headlands, breakwaters, Roman piers, bay geometry.
    /// 0.90 fully exposed … 0.50 enclosed bay.
    public let exposureCoefficient: Double

    /// Direction from the beach out to open sea, degrees true.
    /// ~270 for Israel's west-facing Mediterranean coast.
    public let shorelineNormalDegrees: Double

    /// Nominal water depth at the break, metres. Drives the shoaling
    /// calculation and the 0.78 breaking cap.
    public let breakDepthMeters: Double

    /// Nearest ISRAMAR station, when one is close enough to be a useful check.
    public let buoyStationID: String?

    public init(
        id: String,
        nameHebrew: String,
        nameEnglish: String,
        latitude: Double,
        longitude: Double,
        basin: Basin,
        exposureCoefficient: Double,
        shorelineNormalDegrees: Double,
        breakDepthMeters: Double,
        buoyStationID: String? = nil
    ) {
        self.id = id
        self.nameHebrew = nameHebrew
        self.nameEnglish = nameEnglish
        self.latitude = latitude
        self.longitude = longitude
        self.basin = basin
        self.exposureCoefficient = exposureCoefficient
        self.shorelineNormalDegrees = shorelineNormalDegrees
        self.breakDepthMeters = breakDepthMeters
        self.buoyStationID = buoyStationID
    }
}

public enum SpotCatalogError: Error, Equatable, Sendable {
    case resourceMissing
}

/// Loads the bundled spot catalogue.
public enum SpotCatalog {
    /// - Parameter bundle: defaults to the package's own resource bundle.
    ///   It cannot be spelled as a default argument value, because `Bundle.module`
    ///   is internal and a public function's defaults are inlined into callers.
    public static func load(
        from bundle: Bundle? = nil,
        resource: String = "spots"
    ) throws -> [Spot] {
        let bundle = bundle ?? .module
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw SpotCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Spot].self, from: data)
    }
}
