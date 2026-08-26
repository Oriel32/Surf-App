import Foundation
import Testing
@testable import SurfCore

@Suite("Rule tables")
struct RuleTableTests {
    private let table = RuleTable<String>([
        .init(from: 0, "low"),
        .init(from: 10, "mid"),
        .init(from: 20, "high")
    ])

    @Test("A bound is inclusive, so a value sitting exactly on it takes the higher band")
    func boundsAreInclusive() {
        #expect(table.value(for: 9.999) == "low")
        #expect(table.value(for: 10) == "mid")
        #expect(table.value(for: 19.999) == "mid")
        #expect(table.value(for: 20) == "high")
    }

    @Test("The first row is the floor, so the lookup is total and needs no fallback")
    func floorCatchesEverythingBelow() {
        #expect(table.value(for: -1) == "low")
        #expect(table.value(for: -.infinity) == "low")
    }

    @Test("The top band is open-ended")
    func topBandIsOpen() {
        #expect(table.value(for: 100_000) == "high")
        #expect(table.upperBound(atRow: 0) == 10)
        #expect(table.upperBound(atRow: 2) == nil)
    }

    @Test("A band can be read back to the bound it starts at")
    func reverseLookup() {
        #expect(table.lowerBound(of: "mid") == 10)
        #expect(table.lowerBound(of: "absent") == nil)
    }
}

@Suite("Wind strength bands")
struct WindStrengthTests {
    @Test("The research doc's strength bands are reproduced exactly")
    func documentedBands() {
        // 0-10 weak, 10-15 moderate, 15+ strong.
        #expect(WindStrength.strength(forKnots: 0) == .weak)
        #expect(WindStrength.strength(forKnots: 9.9) == .weak)
        #expect(WindStrength.strength(forKnots: 10) == .moderate)
        #expect(WindStrength.strength(forKnots: 14.9) == .moderate)
        #expect(WindStrength.strength(forKnots: 15) == .strong)
        #expect(WindStrength.strength(forKnots: 40) == .strong)
    }

    @Test("Conditions report their own strength band")
    func conditionsCarryStrength() {
        #expect(SpotConditions.fixture(windSpeedMPS: mps(knots: 6)).windStrength == .weak)
        #expect(SpotConditions.fixture(windSpeedMPS: mps(knots: 12)).windStrength == .moderate)
        #expect(SpotConditions.fixture(windSpeedMPS: mps(knots: 18)).windStrength == .strong)
    }

    @Test("Every band carries both a Hebrew and an English name")
    func everyBandIsLocalised() {
        for strength in WindStrength.allCases {
            #expect(!strength.hebrew.isEmpty)
            #expect(!strength.english.isEmpty)
        }
    }
}

@Suite("Score bands")
struct ScoreBandTests {
    @Test("The usable threshold is shared with the window finder, not restated")
    func usableThresholdIsShared() {
        // A row painted as usable that the window finder then refuses to
        // recommend is the app saying two different things at once.
        #expect(ScoreBand.band(forScore: WindowFinder.usableScore) == .fair)
        #expect(ScoreBand.band(forScore: WindowFinder.usableScore - 1) == .poor)
        #expect(ScoreBand.table.lowerBound(of: .fair) == Double(WindowFinder.usableScore))
    }

    @Test("Every score from 0 to 100 lands in a band")
    func wholeRangeIsCovered() {
        var previous = ScoreBand.poor
        for score in 0...100 {
            let band = ScoreBand.band(forScore: score)
            #expect(band.lowerBoundOrZero >= previous.lowerBoundOrZero)
            previous = band
        }
        #expect(ScoreBand.band(forScore: 0) == .poor)
        #expect(ScoreBand.band(forScore: 100) == .excellent)
    }

    @Test("A colour never travels without its word")
    func colourNeverCarriesAlone() {
        // Verified in greyscale: every colour-coded state also has a word, so a
        // red-green colourblind reader loses nothing.
        for band in ScoreBand.allCases {
            #expect(!band.hebrew.isEmpty)
            #expect(!band.english.isEmpty)
        }
        for state in SeaState.allCases {
            #expect(!state.hebrew.isEmpty)
            #expect(!state.english.isEmpty)
        }
    }

    @Test("The hero blue is spent only on the states that earn it")
    func heroIsRare() {
        // The glassy blue is the app's rare moment; handing it to ordinary
        // states is what would stop it landing when it is real.
        let heroStates = SeaState.allCases.filter { $0.colorToken == .hero }
        #expect(heroStates == [.glassy])

        let heroBands = ScoreBand.allCases.filter { $0.colorToken == .hero }
        #expect(heroBands == [.excellent])
    }
}

private extension ScoreBand {
    var lowerBoundOrZero: Double { ScoreBand.table.lowerBound(of: self) ?? 0 }
}
