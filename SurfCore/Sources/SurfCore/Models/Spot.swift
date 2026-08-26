import Foundation

/// Which body of water a spot sits in. This is not decoration — global wave
/// models do not resolve the Gulf of Eilat, and their output there is
/// meaningless, so the basin selects an entirely different code path.
public enum Basin: String, Sendable, Codable, Equatable {
    case mediterranean
    case gulfOfEilat
}

/// The arc of swell bearings a spot can actually receive.
///
/// Refraction already drops anything arriving from behind the shoreline, but
/// that is a half-plane and real coastlines are not. Headlands, breakwaters and
/// the Roman piers at Caesarea shadow specific *sectors*: a swell can be square
/// onto the beach normal and still be blocked by the mole just up the coast.
///
/// Expressed as the arc running clockwise from `fromDegrees` to `toDegrees`, so
/// it wraps through north the way a real window usually does.
public struct SwellWindow: Sendable, Codable, Equatable {
    public let fromDegrees: Double
    public let toDegrees: Double

    public init(fromDegrees: Double, toDegrees: Double) {
        self.fromDegrees = fromDegrees
        self.toDegrees = toDegrees
    }

    /// Whether swell arriving *from* this bearing reaches the break.
    public func admits(_ bearingDegrees: Double) -> Bool {
        let bearing = Compass.normalize(bearingDegrees)
        let start = Compass.normalize(fromDegrees)
        let end = Compass.normalize(toDegrees)
        // A window that does not wrap is a simple range; one that wraps through
        // 0 is the union of the two ends.
        return start <= end
            ? (bearing >= start && bearing <= end)
            : (bearing >= start || bearing <= end)
    }
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

    /// The sector this break is open to. `nil` means "no sector data", which
    /// leaves refraction as the only shadowing — the behaviour before windows
    /// existed.
    ///
    /// Deliberately unpopulated in `spots.json`. Every value here is a claim
    /// about a specific headland or mole, and inventing eleven of them from a
    /// map would be exactly the kind of plausible-looking number this project
    /// refuses to ship. They need local knowledge or bathymetry.
    public let swellWindow: SwellWindow?

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
        buoyStationID: String? = nil,
        swellWindow: SwellWindow? = nil
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
        self.swellWindow = swellWindow
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
