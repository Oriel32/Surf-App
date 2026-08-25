import Foundation
import Testing
@testable import SurfCore

@Suite("Match score — surfing")
struct SurfingScoreTests {
    private let surfer = UserProfile(sport: .surfing, skill: .intermediate)

    @Test("A glassy waist-to-chest morning scores near the top")
    func idealMorningScoresHigh() {
        let conditions = SpotConditions.fixture(
            waveHeightMeters: 0.9,
            periodSeconds: 8,
            windSpeedMPS: mps(knots: 6),
            windRelation: .offshore
        )
        #expect(MatchScoreEngine.score(for: conditions, profile: surfer).value > 85)
    }

    @Test("The same swell blown out by a 20-knot onshore scores near the bottom")
    func blownOutScoresLow() {
        // Identical size and period to the ideal case — only the wind differs.
        // A weighted sum would still return about 70 here, which is why wind
        // multiplies rather than adds.
        let conditions = SpotConditions.fixture(
            waveHeightMeters: 0.9,
            periodSeconds: 8,
            windSpeedMPS: mps(knots: 20),
            windRelation: .onshore,
            seaState: .choppy
        )
        #expect(MatchScoreEngine.score(for: conditions, profile: surfer).value < 30)
    }

    @Test("Short-period wind slop scores below real groundswell of the same size")
    func periodSeparatesSlopFromSwell() {
        let slop = SpotConditions.fixture(waveHeightMeters: 0.9, periodSeconds: 4)
        let groundswell = SpotConditions.fixture(waveHeightMeters: 0.9, periodSeconds: 9)

        let slopScore = MatchScoreEngine.score(for: slop, profile: surfer).value
        let swellScore = MatchScoreEngine.score(for: groundswell, profile: surfer).value

        #expect(swellScore > slopScore)
    }

    @Test("A flat sea cannot score well no matter how perfect the wind")
    func flatSeaScoresLow() {
        let conditions = SpotConditions.fixture(
            waveHeightMeters: 0.05,
            periodSeconds: 9,
            windSpeedMPS: mps(knots: 3),
            windRelation: .offshore
        )
        #expect(MatchScoreEngine.score(for: conditions, profile: surfer).value < 20)
    }

    @Test("The score reports the components behind it")
    func scoreExplainsItself() {
        let score = MatchScoreEngine.score(for: .fixture(), profile: surfer)
        #expect(score.components["height"] != nil)
        #expect(score.components["period"] != nil)
        #expect(score.components["wind"] != nil)
    }
}

@Suite("Match score — sport inversion")
struct SportInversionTests {
    @Test("A 20-knot side-shore is a ruined surf and a good kite session")
    func windInvertsBetweenSports() {
        let windy = SpotConditions.fixture(
            waveHeightMeters: 0.9,
            periodSeconds: 8,
            windSpeedMPS: mps(knots: 20),
            windRelation: .sideShore,
            seaState: .choppy
        )

        let surf = MatchScoreEngine.score(
            for: windy,
            profile: UserProfile(sport: .surfing, skill: .intermediate)
        ).value
        let kite = MatchScoreEngine.score(
            for: windy,
            profile: UserProfile(sport: .kitesurfing, skill: .intermediate)
        ).value

        #expect(kite > 80)
        #expect(surf < 30)
        #expect(kite > surf)
    }

    @Test("A windless day is useless for kiting however clean the sea")
    func kiteNeedsWind() {
        let glassy = SpotConditions.fixture(
            waveHeightMeters: 0.8,
            windSpeedMPS: mps(knots: 3),
            windRelation: .offshore
        )
        let kite = MatchScoreEngine.score(
            for: glassy,
            profile: UserProfile(sport: .kitesurfing, skill: .advanced)
        ).value
        #expect(kite < 15)
    }

    @Test("Wing foil gets going in lighter wind than kite")
    func wingFoilStartsEarlier() {
        let moderate = SpotConditions.fixture(
            waveHeightMeters: 0.5,
            windSpeedMPS: mps(knots: 13),
            windRelation: .sideShore
        )
        let kite = MatchScoreEngine.score(
            for: moderate, profile: UserProfile(sport: .kitesurfing, skill: .advanced)
        ).value
        let wing = MatchScoreEngine.score(
            for: moderate, profile: UserProfile(sport: .wingFoil, skill: .advanced)
        ).value
        #expect(wing > kite)
    }
}

@Suite("Match score — safety suppression")
struct ScoreSuppressionTests {
    @Test("An offshore drift hazard crushes the SUP score despite a perfect surface")
    func supIsSuppressedByOffshoreWind() {
        // Flat, glassy, inviting — and the exact conditions that carry paddlers
        // out to sea. The number must not disagree with the banner.
        let deceptive = SpotConditions.fixture(
            waveHeightMeters: 0.2,
            periodSeconds: 4,
            windSpeedMPS: mps(knots: 12),
            windRelation: .offshore,
            seaState: .glassy
        )
        let sup = MatchScoreEngine.score(
            for: deceptive,
            profile: UserProfile(sport: .sup, skill: .beginner)
        ).value
        #expect(sup < 10)
    }

    @Test("The same sea scores well for SUP once the wind drops")
    func supScoresWellWhenCalm() {
        let calm = SpotConditions.fixture(
            waveHeightMeters: 0.2,
            periodSeconds: 4,
            windSpeedMPS: mps(knots: 3),
            windRelation: .offshore,
            seaState: .glassy
        )
        let sup = MatchScoreEngine.score(
            for: calm,
            profile: UserProfile(sport: .sup, skill: .beginner)
        ).value
        #expect(sup > 80)
    }

    @Test("A beginner is scored more conservatively than an advanced surfer")
    func skillLevelChangesTheScore() {
        let offshoreMorning = SpotConditions.fixture(
            waveHeightMeters: 1.2,
            periodSeconds: 9,
            windSpeedMPS: mps(knots: 10),
            windRelation: .offshore
        )
        let beginner = MatchScoreEngine.score(
            for: offshoreMorning, profile: UserProfile(sport: .surfing, skill: .beginner)
        ).value
        let advanced = MatchScoreEngine.score(
            for: offshoreMorning, profile: UserProfile(sport: .surfing, skill: .advanced)
        ).value

        #expect(advanced > beginner)
    }

    @Test("Scores are always within 0...100")
    func scoresStayInRange() {
        for height in stride(from: 0.0, through: 4.0, by: 0.25) {
            for knots in stride(from: 0.0, through: 40.0, by: 5.0) {
                for relation in WindRelation.allCases {
                    for sport in Sport.allCases {
                        let conditions = SpotConditions.fixture(
                            waveHeightMeters: height,
                            periodSeconds: 8,
                            windSpeedMPS: mps(knots: knots),
                            windRelation: relation
                        )
                        let value = MatchScoreEngine.score(
                            for: conditions,
                            profile: UserProfile(sport: sport, skill: .intermediate)
                        ).value
                        #expect(value >= 0 && value <= 100)
                    }
                }
            }
        }
    }
}
