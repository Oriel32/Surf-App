import Foundation
import Testing
@testable import SurfCore

@Suite("Wetsuit recommendation")
struct WetsuitTests {
    @Test("The four categories the research names are all reachable")
    func everyCategoryIsReachable() {
        // February sea through August sea on this coast, roughly 16 to 30 C.
        #expect(Wetsuit.recommendation(forWaterTemperatureC: 16) == .winterSuit)
        #expect(Wetsuit.recommendation(forWaterTemperatureC: 20) == .summerSuit)
        #expect(Wetsuit.recommendation(forWaterTemperatureC: 24) == .lycra)
        #expect(Wetsuit.recommendation(forWaterTemperatureC: 30) == .swimsuit)
    }

    @Test("Colder water never recommends less neoprene")
    func monotonicInTemperature() {
        // The ladder must not invert anywhere. Getting this backwards puts
        // someone in a swimsuit in a February sea.
        var previousBound = -Double.infinity
        for celsius in stride(from: -2.0, through: 34.0, by: 0.5) {
            let bound = Wetsuit.table.lowerBound(of: .recommendation(forWaterTemperatureC: celsius)) ?? 0
            #expect(bound >= previousBound)
            previousBound = bound
        }
    }

    @Test("Every recommendation is localised and has a glyph")
    func everyCategoryIsPresentable() {
        for suit in Wetsuit.allCases {
            #expect(!suit.hebrew.isEmpty)
            #expect(!suit.english.isEmpty)
            #expect(!suit.symbolName.isEmpty)
        }
    }
}

@Suite("Height units")
struct HeightUnitTests {
    @Test("Metres pass through untouched")
    func metresAreIdentity() {
        #expect(HeightUnit.meters.convert(fromMeters: 0.8) == 0.8)
    }

    @Test("Feet use the exact conversion, not a field approximation")
    func feetConversion() {
        let converted = HeightUnit.feet.convert(fromMeters: 1.0)
        #expect(abs(converted - 3.280_839_895) < 1e-9)
    }

    @Test("The unit reaches the rendered string and its spoken form")
    func unitReachesPresentation() {
        let conditions = SpotConditions.fixture(waveHeightMeters: 1.0)

        let metric = Translator.present(conditions)
        #expect(metric.waveHeightText.contains("1.0"))
        #expect(metric.waveHeightText.contains(HebrewText.geresh))

        let imperial = Translator.present(conditions, heightUnit: .feet)
        // 1.0 m significant = 3.3 ft, and the sets at 1.27x = 4.2 ft. The
        // rendered range spans both; the spoken label quotes the sets.
        #expect(imperial.waveHeightText.contains("3.3"))
        #expect(imperial.waveHeightText.contains("4.2"))
        #expect(imperial.accessibilityLabel.contains("4.2"))
        // Spoken form drops the abbreviation and the direction controls.
        #expect(!imperial.accessibilityLabel.contains(HebrewText.leftToRightIsolate))
    }

    @Test("Switching units never drops the slang half of the line")
    func slangSurvivesUnitChange() {
        // The rule is metric value AND anatomical term, in either unit.
        let conditions = SpotConditions.fixture(waveHeightMeters: 0.8)
        for unit in HeightUnit.allCases {
            let presented = Translator.present(conditions, heightUnit: unit)
            #expect(presented.waveLine.contains(WaveBand.knee.hebrew))
            #expect(presented.waveLine.contains(presented.waveHeightText))
        }
    }

    @Test("Wind has no alternative unit, because knots are the marine standard")
    func windIsAlwaysKnots() {
        let conditions = SpotConditions.fixture(windSpeedMPS: mps(knots: 8))
        for unit in HeightUnit.allCases {
            #expect(Translator.present(conditions, heightUnit: unit).windLine.contains("8"))
        }
    }
}
