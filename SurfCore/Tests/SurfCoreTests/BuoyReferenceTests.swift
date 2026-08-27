import Foundation
import Testing
@testable import SurfCore

@Suite("Buoy reference")
struct BuoyReferenceTests {
    private let hadera = try! #require(IsramarClient.stations["hadera"])

    @Test("Distance matches the real geography of this coast")
    func distanceIsRight() throws {
        let spots = try SpotCatalog.load()
        let batYam = try #require(spots.first { $0.id == "bat-yam" })
        let caesarea = try #require(spots.first { $0.id == "caesarea" })

        let far = IsramarClient.reference(for: hadera, from: batYam)
        let near = IsramarClient.reference(for: hadera, from: caesarea)

        // Bat Yam is a little over fifty kilometres south of the buoy;
        // Caesarea is a few kilometres north of it.
        #expect(far.distanceKilometres > 45 && far.distanceKilometres < 60)
        #expect(near.distanceKilometres < 10)
    }

    @Test("Bearing points the right way up and down the coast")
    func bearingIsRight() throws {
        let spots = try SpotCatalog.load()
        let batYam = try #require(spots.first { $0.id == "bat-yam" })
        let haifa = try #require(spots.first { $0.id == "haifa-backdoor" })

        // From Bat Yam the buoy is north; from Haifa it is south.
        #expect(IsramarClient.reference(for: hadera, from: batYam).direction == .north)
        #expect(IsramarClient.reference(for: hadera, from: haifa).direction == .south)
    }

    @Test("Nearby readings are called local, distant ones are not")
    func localityHasAThreshold() throws {
        let spots = try SpotCatalog.load()
        let hadera = try #require(spots.first { $0.id == "hadera" })
        let ashkelon = try #require(spots.first { $0.id == "ashkelon-delilah" })

        #expect(IsramarClient.reference(for: self.hadera, from: hadera).isLocal)
        #expect(!IsramarClient.reference(for: self.hadera, from: ashkelon).isLocal)
    }

    @Test("A distant reading always states its distance")
    func distantReadingsCarryContext() throws {
        // Ninety-odd kilometres away is still useful ground truth for the
        // open-sea model, and still not a measurement of that beach. Showing it
        // without the distance would be the same dishonesty as showing a stale
        // reading as current.
        let spots = try SpotCatalog.load()
        let ashkelon = try #require(spots.first { $0.id == "ashkelon-delilah" })
        let summary = IsramarClient.reference(for: hadera, from: ashkelon).hebrewSummary

        #expect(summary.contains("חדרה"))
        #expect(summary.contains("ק״מ"))
        #expect(summary.contains(CompassPoint.north.hebrewNoun))
    }

    @Test("A local reading does not clutter itself with a distance")
    func localReadingsStaySimple() throws {
        let spots = try SpotCatalog.load()
        let hadera = try #require(spots.first { $0.id == "hadera" })
        let summary = IsramarClient.reference(for: self.hadera, from: hadera).hebrewSummary
        #expect(!summary.contains("ק״מ"))
    }

    @Test("Every Mediterranean spot now has a buoy to check against")
    func everyMediterraneanSpotHasAStation() throws {
        // The complaint that started this: eight of twelve spots said "no buoy"
        // when one perfectly good regional buoy was live the whole time.
        let spots = try SpotCatalog.load()
        for spot in spots where spot.basin == .mediterranean {
            #expect(spot.buoyStationID == "hadera", "\(spot.id) has no station")
        }
    }

    @Test("Eilat has no buoy, and claiming otherwise would be a lie")
    func eilatStaysUnreferenced() throws {
        // A Mediterranean buoy says nothing whatever about the Gulf of Eilat.
        let spots = try SpotCatalog.load()
        let eilat = try #require(spots.first { $0.id == "eilat-village" })
        #expect(eilat.buoyStationID == nil)
    }

    @Test("Shikmona stays in the registry even though nothing points at it")
    func deadStationIsKept() {
        // Its frozen-since-January payload is what the staleness gate is tested
        // against; deleting it would delete the regression test's subject.
        #expect(IsramarClient.stations["shikmona"] != nil)
    }

    @Test("Distance is symmetric and zero to itself")
    func geometrySanity() {
        let d = Geo.distanceKilometres(
            fromLatitude: 32.0, longitude: 34.7, toLatitude: 32.0, longitude: 34.7
        )
        #expect(d < 1e-9)
        let there = Geo.distanceKilometres(
            fromLatitude: 32.0, longitude: 34.7, toLatitude: 32.5, longitude: 34.9
        )
        let back = Geo.distanceKilometres(
            fromLatitude: 32.5, longitude: 34.9, toLatitude: 32.0, longitude: 34.7
        )
        #expect(abs(there - back) < 1e-9)
    }
}
