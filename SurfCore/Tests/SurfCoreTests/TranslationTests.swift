import Foundation
import Testing
@testable import SurfCore

@Suite("Wave height to local slang")
struct WaveBandTests {
    /// A long period, so every height in these cases clears the break point and
    /// the anatomical ladder is what is being tested.
    private func band(_ meters: Double, period: Double = 9, seaState: SeaState = .fair) -> WaveBand {
        WaveBand.band(forHeightMeters: meters, periodSeconds: period, seaState: seaState)
    }

    @Test("Named heights land in the band the community uses")
    func canonicalHeights() {
        #expect(band(0.55) == .ankle)
        #expect(band(0.80) == .knee)
        #expect(band(1.00) == .waist)
        #expect(band(1.30) == .chest)
        #expect(band(1.50) == .shoulder)
        #expect(band(1.90) == .head)
        #expect(band(3.00) == .doubleHead)
    }

    @Test("GoSurf's own words for Bat Yam, 2026-08-27")
    func matchesGoSurfOnTheDayItWasMeasured() {
        // The two hours the ledger records side by side. These are not chosen
        // boundaries — they are the heights the pipeline produced that day, and
        // the words GoSurf published for the same hours.
        // See calibration/bat-yam-comparison.md.
        #expect(band(0.48, period: 6.3, seaState: .fair).hebrew == "ים גלי")
        #expect(band(0.51, period: 6.3, seaState: .fair).hebrew == "קרסול")
    }

    @Test("A dead flat sea is flat, not ankle-high")
    func flatIsFlat() {
        #expect(band(0.0) == .flat)
        #expect(band(0.05) == .flat)
    }

    @Test("Below the break point there is a sea state, never a body part")
    func belowBreakingIsNotAnatomical() {
        // GoSurf: "גלים נשברים מ-50 ס״מ" — naming a body part for water that
        // does not break is the overstatement this whole calibration was about.
        #expect(band(0.30, period: 6).isBreakingSurf == false)
        #expect(band(0.45, period: 6) == .wavySea)

        // `ים נוח` is the swimmer's sea: small AND smooth. Glass alone does not
        // earn it — GoSurf called a 0.46 m sea `ים גלי` in a 4 km/h wind.
        #expect(band(0.45, period: 6, seaState: .glassy) == .wavySea)
        #expect(band(0.20, period: 6, seaState: .glassy) == .calmSea)
        #expect(band(0.20, period: 6, seaState: .choppy) == .wavySea)
    }

    @Test("The break point moves with the period, as GoSurf says it does")
    func breakPointFollowsPeriod() {
        // A short-period slop needs more height to break; a groundswell needs less.
        #expect(band(0.50, period: 4) == .wavySea)
        #expect(band(0.50, period: 6) == .ankle)
        #expect(band(0.45, period: 10) == .ankle)

        #expect(abs(SurfBreaking.minimumHeightMeters(periodSeconds: 6) - 0.50) < 0.01)
        #expect(SurfBreaking.minimumHeightMeters(periodSeconds: 4) > 0.60)
        #expect(SurfBreaking.minimumHeightMeters(periodSeconds: 12) < 0.36)
    }

    @Test("Bands never go backwards as height rises")
    func bandsAreMonotonic() {
        var previous = WaveBand.flat
        for step in 0...400 {
            let current = band(Double(step) / 100)
            #expect(current.lowerBoundMeters >= previous.lowerBoundMeters)
            previous = current
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

    @Test("Chop in the water reads as chop even when the mean wind looks ideal")
    func partitionCanCallItChoppy() {
        // The 2026-08-29 Bat Yam case in miniature: a 9-knot side-shore, which
        // every mean-speed rule here calls fine, over a sea a fifth of whose
        // energy is 2.5-second slop.
        let state = SeaStateClassifier.classify(
            heightMeters: 0.65,
            windSpeedMPS: mps(knots: 9),
            relation: .sideShore,
            windSeaEnergyShare: 0.20
        )
        #expect(state == .choppy)

        // Just under the threshold, the same hour is fair.
        let cleaner = SeaStateClassifier.classify(
            heightMeters: 0.65,
            windSpeedMPS: mps(knots: 9),
            relation: .sideShore,
            windSeaEnergyShare: 0.11
        )
        #expect(cleaner == .fair)
    }

    @Test("A hard gust reads as chop before the sea has answered it")
    func gustCanCallItChoppy() {
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 9),
            relation: .sideShore,
            windGustMPS: mps(knots: 21)
        )
        #expect(state == .choppy)
    }

    @Test("An unpartitioned sea is not charged for a share nobody measured")
    func absentPartitionChangesNothing() {
        // A source that does not separate the trains must produce exactly the
        // answer it did before the rule existed, rather than a guess.
        let state = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 8),
            relation: .onshore,
            windSeaEnergyShare: nil
        )
        #expect(state == .fair)
    }

    @Test("Glass survives both new rules — the hero state is not collateral damage")
    func glassyStillWins() {
        // The glassy branch deliberately sits ahead of the chop rules. A calm
        // morning with an old wind sea still running, and an offshore morning
        // with a gusty land breeze, both stay `גלאסי`.
        let calm = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 3),
            relation: .onshore,
            windSeaEnergyShare: 0.45,
            windGustMPS: mps(knots: 22)
        )
        #expect(calm == .glassy)

        let offshore = SeaStateClassifier.classify(
            heightMeters: 0.8,
            windSpeedMPS: mps(knots: 10),
            relation: .offshore,
            windSeaEnergyShare: 0.40,
            windGustMPS: mps(knots: 25)
        )
        #expect(offshore == .glassy)
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
