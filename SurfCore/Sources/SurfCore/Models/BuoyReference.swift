import Foundation

/// Great-circle geometry, for relating a spot to the instrument measuring it.
public enum Geo {
    static let earthRadiusKilometres = 6371.0

    /// Haversine distance in kilometres.
    public static func distanceKilometres(
        fromLatitude lat1: Double, longitude lon1: Double,
        toLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(p1) * cos(p2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKilometres * asin(min(1, a.squareRoot()))
    }

    /// Initial bearing in degrees true, from the first point toward the second.
    public static func bearingDegrees(
        fromLatitude lat1: Double, longitude lon1: Double,
        toLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let y = sin(dLon) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dLon)
        return Compass.normalize(atan2(y, x) * 180 / .pi)
    }
}

/// A measuring station, and where it sits relative to the spot being forecast.
///
/// ## Why the distance travels with the reading
/// Israel has exactly one live wave buoy. Hadera is a perfectly good check on
/// the *open-sea model* anywhere along this straight, uniformly west-facing
/// coast — but it is not a measurement of Ashkelon, ninety-four kilometres
/// south, and displaying it as though it were would be the same class of
/// dishonesty as showing a stale reading as current.
///
/// So the reading is shown everywhere and the distance is shown with it. The
/// user gets ground truth and the context to judge how much of it applies.
public struct BuoyReference: Sendable, Equatable {
    public let stationID: String
    public let nameHebrew: String
    public let distanceKilometres: Double
    /// Bearing from the spot toward the buoy, degrees true.
    public let bearingDegrees: Double

    public init(
        stationID: String,
        nameHebrew: String,
        distanceKilometres: Double,
        bearingDegrees: Double
    ) {
        self.stationID = stationID
        self.nameHebrew = nameHebrew
        self.distanceKilometres = distanceKilometres
        self.bearingDegrees = bearingDegrees
    }

    public var direction: CompassPoint {
        CompassPoint.point(forDegrees: bearingDegrees)
    }

    /// Close enough that the reading describes roughly this stretch of coast.
    ///
    /// Not a display gate — the reading is shown either way — but the honest
    /// line between "the sea here" and "the sea up the coast".
    public var isLocal: Bool {
        distanceKilometres <= 25
    }

    /// `מצוף חדרה · 52 ק״מ · צפון`
    public var hebrewSummary: String {
        let km = HebrewText.ltr(String(format: "%.0f", distanceKilometres))
        return isLocal
            ? "מצוף \(nameHebrew)"
            : "מצוף \(nameHebrew) · \(km) ק״מ \(direction.hebrewNoun)"
    }
}
