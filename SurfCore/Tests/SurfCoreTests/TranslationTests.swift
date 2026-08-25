import Foundation
import Testing
@testable import SurfCore

@Suite("Wave height to local slang")
struct WaveBandTests {
    @Test("Named heights land in the band the community uses")
    func canonicalHeights() {
        #expect(WaveBand.band(forHeightMeters: 0.30) == .ankleToKnee)
        #expect(WaveBand.band(forHeightMeters: 0.80) == .waistToChest)
        #expect(WaveBand.band(forHeightMeters: 1.20) == .shoulderToHead)
        #expect(WaveBand.band(forHeightMeters: 3.00) == .doubleOverhead)
    }

    @Test("A dead flat sea is flat, not ankle-high")
    func flatIsFlat() {
        #expect(WaveBand.band(forHeightMeters: 0.0) == .flat)
        #expect(WaveBand.band(forHeightMeters: 0.15) == .flat)
    }

    @Test("The gaps the research leaves between bands are closed")
    func noGapsBetweenBands() {
        // The source doc names 0.20-0.40, 0.50-0.90 and 1.00-1.50, leaving 0.40-0.50
        // and 0.90-1.00 unnamed. A band table with holes drops real conditions
        // on the floor, so these must resolve to the band below.
        #expect(WaveBand.band(forHeightMeters: 0.45) == .ankleToKnee)
        #expect(WaveBand.band(forHeightMeters: 0.95) == .waistToChest)
    }

    @Test("Bands never go backwards as height rises")
    func bandsAreMonotonic() {
        var previous = WaveBand.flat
        for step in 0...400 {
            let band = WaveBand.band(forHeightMeters: Double(step) / 100)
            #expect(band.lowerBoundMeters >= previous.lowerBoundMeters)
            previous = band
        }
    }

    @Test("Every band carries both a Hebrew and an English name")
    func everyBandIsLocalised() {
        for band in WaveBand.allCases {
            #expect(!band.hebrew.isEmpty)
            #expect(!band.english.isEmpty)
        }
    }
}

@Suite("Sea state texture")
struct SeaStateTests {
    @Test("No swell means flat, whatever the wind is doing")
    func noSwellIsFlat() {
        let state = SeaStateClassifier.classify(
            heightMeters: 0.05,
            windSpeedMPS: mps(knots: 18),
            relation: .onshore
        )
        #expect(state == .flat)
    }

    @Test("A light offshore over real swell is glassy")
    func lightOffshoreIsGlassy() {
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 6),
            relation: .offshore
        )
        #expect(state == .glassy)
    }

    @Test("Near-windless conditions are glassy regardless of direction")
    func windlessIsGlassy() {
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 2),
            relation: .onshore
        )
        #expect(state == .glassy)
    }

    @Test("A brisk onshore is choppy")
    func briskOnshoreIsChoppy() {
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 18),
            relation: .onshore
        )
        #expect(state == .choppy)
    }

    @Test("A moderate onshore is neither glassy nor choppy")
    func moderateOnshoreIsFair() {
        // The research names only flat/glassy/choppy; forcing this day into one
        // of those would misdescribe most of the Israeli summer.
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 8),
            relation: .onshore
        )
        #expect(state == .fair)
    }
}

@Suite("Spot catalogue")
struct SpotCatalogTests {
    @Test("The bundled catalogue loads and is internally sane")
    func catalogueLoads() throws {
        let spots = try SpotCatalog.load()
        #expect(!spots.isEmpty)

        for spot in spots {
            #expect(spot.exposureCoefficient > 0 && spot.exposureCoefficient <= 1.0)
            #expect(spot.breakDepthMeters > 0)
            #expect(spot.shorelineNormalDegrees >= 0 && spot.shorelineNormalDegrees < 360)
            #expect(!spot.nameHebrew.isEmpty)
        }

        #expect(Set(spots.map(\.id)).count == spots.count, "spot ids must be unique")
    }

    @Test("Eilat is flagged as its own basin")
    func eilatIsSeparateBasin() throws {
        let spots = try SpotCatalog.load()
        let eilat = try #require(spots.first { $0.id == "eilat-village" })
        #expect(eilat.basin == .gulfOfEilat)
    }

    @Test("Sheltering matches the researched coefficients")
    func shelteringCoefficients() throws {
        let spots = try SpotCatalog.load()
        let haifa = try #require(spots.first { $0.id == "haifa-backdoor" })
        let palmachim = try #require(spots.first { $0.id == "palmachim" })
        let caesarea = try #require(spots.first { $0.id == "caesarea" })

        #expect(haifa.exposureCoefficient == 0.50)
        #expect(palmachim.exposureCoefficient == 0.90)
        #expect(caesarea.exposureCoefficient == 0.70)
    }
}
