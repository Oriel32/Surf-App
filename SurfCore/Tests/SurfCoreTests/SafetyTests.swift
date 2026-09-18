import Foundation
import Testing
@testable import SurfCore

@Suite("Offshore drift hazard")
struct OffshoreDriftTests {
    private func conditions(knots: Double, relation: WindRelation = .offshore) -> SpotConditions {
        SpotConditions.fixture(
            waveHeightMeters: 0.4,
            periodSeconds: 6,
            windSpeedMPS: mps(knots: knots),
            windRelation: relation,
            seaState: .glassy
        )
    }

    @Test("A beginner is warned in a 12-knot offshore")
    func beginnerIsWarned() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 12),
            profile: UserProfile(sport: .surfing, skill: .beginner)
        )
        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.severity == .danger)
    }

    @Test("An advanced surfer is not warned at the same wind")
    func advancedIsNotWarnedAtModerateWind() {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 12),
            profile: UserProfile(sport: .surfing, skill: .advanced)
        )
        #expect(!alerts.contains { $0.kind == .offshoreDrift })
    }

    @Test("An advanced surfer is warned once it really blows")
    func advancedIsWarnedAtStrongWind() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 18),
            profile: UserProfile(sport: .surfing, skill: .advanced)
        )
        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.severity == .danger)
    }

    @Test("A paddler on a floating craft is always the danger case")
    func supIsAlwaysDanger() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 9),
            profile: UserProfile(sport: .sup, skill: .advanced)
        )
        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.severity == .danger)
    }

    @Test("An onshore gale raises no drift warning")
    func onshoreWindDoesNotDrift() {
        // A hard onshore is unpleasant, not a drift hazard — it pushes you back
        // to the beach. Warning here would train users to ignore the banner.
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 25, relation: .onshore),
            profile: UserProfile(sport: .sup, skill: .beginner)
        )
        #expect(!alerts.contains { $0.kind == .offshoreDrift })
    }

    @Test("A cross-offshore wind still drifts")
    func crossOffshoreDrifts() {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 14, relation: .crossOffshore),
            profile: UserProfile(sport: .surfing, skill: .beginner)
        )
        #expect(alerts.contains { $0.kind == .offshoreDrift })
    }

    @Test("The warning names the illusion, not just the wind speed")
    func warningExplainsTheIllusion() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(knots: 14),
            profile: UserProfile(sport: .sup, skill: .beginner)
        )
        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })

        // The hazard is that the sea *looks* calm. A body that only reports the
        // wind speed does not tell a beginner why the flat water is the problem.
        #expect(drift.hebrewBody.contains("אשליה"))
        #expect(drift.hebrewBody.contains("סאפ"))
        #expect(!drift.hebrewTitle.isEmpty)
    }
}

/// The station is a second witness, and it is only ever allowed to speak up.
@Suite("Measured wind and the drift alert")
struct MeasuredWindDriftTests {
    private func measured(
        knots: Double,
        relation: WindRelation = .offshore,
        at moment: Date = .utc(2026, 9, 18, 6, 40)
    ) -> MeasuredWind {
        MeasuredWind(
            observation: WindObservation(
                stationID: "178",
                observedAt: moment,
                windSpeedMPS: mps(knots: knots),
                windDirectionDegrees: relation == .offshore ? 90 : 270
            ),
            relation: relation,
            stationNameHebrew: "חוף תל אביב"
        )
    }

    private func conditions(
        modelKnots: Double,
        modelRelation: WindRelation,
        measured: MeasuredWind?
    ) -> SpotConditions {
        var conditions = SpotConditions.fixture(
            waveHeightMeters: 0.4,
            periodSeconds: 6,
            windSpeedMPS: mps(knots: modelKnots),
            windRelation: modelRelation,
            seaState: .glassy
        )
        conditions.measuredWind = measured
        return conditions
    }

    /// The case this exists for: a glassy dawn where the 9 km model cell has the
    /// wind at 4 knots and the mast on the beach is reading 12 offshore.
    @Test("A measured offshore wind raises the alert the model missed")
    func measuredWindRaisesAlert() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(modelKnots: 4, modelRelation: .offshore, measured: measured(knots: 12)),
            profile: UserProfile(sport: .surfing, skill: .beginner)
        )

        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.severity == .danger)
        // It quotes the stronger witness, names the station and timestamps it.
        #expect(drift.hebrewBody.contains("12"))
        #expect(drift.hebrewBody.contains("חוף תל אביב"))
        #expect(drift.hebrewBody.contains("09:40"))
    }

    @Test("A measured onshore wind cannot cancel a modelled offshore hazard")
    func measurementNeverCancels() throws {
        // The mast sits behind the same buildings that make the sea look calm
        // from the sand. A quiet reading is not evidence of a quiet sea.
        let alerts = SafetyEngine.alerts(
            for: conditions(
                modelKnots: 12,
                modelRelation: .offshore,
                measured: measured(knots: 20, relation: .onshore)
            ),
            profile: UserProfile(sport: .surfing, skill: .beginner)
        )

        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.hebrewBody.contains("12"))
        // The onshore measurement is not quoted as though it were the hazard.
        #expect(!drift.hebrewBody.contains("חוף תל אביב"))
    }

    @Test("An onshore model wind with an offshore measurement still warns")
    func measuredAloneIsEnough() {
        let alerts = SafetyEngine.alerts(
            for: conditions(modelKnots: 3, modelRelation: .onshore, measured: measured(knots: 14)),
            profile: UserProfile(sport: .surfing, skill: .intermediate)
        )
        #expect(alerts.contains { $0.kind == .offshoreDrift })
    }

    @Test("A light measured offshore below the threshold warns nobody")
    func lightMeasuredWindIsNotAnAlert() {
        let alerts = SafetyEngine.alerts(
            for: conditions(modelKnots: 3, modelRelation: .onshore, measured: measured(knots: 5)),
            profile: UserProfile(sport: .surfing, skill: .intermediate)
        )
        #expect(!alerts.contains { $0.kind == .offshoreDrift })
    }

    @Test("A paddler is held to the beginner threshold on measured wind too")
    func supIsHeldToTheCautiousThreshold() throws {
        let alerts = SafetyEngine.alerts(
            for: conditions(modelKnots: 2, modelRelation: .onshore, measured: measured(knots: 9)),
            profile: UserProfile(sport: .sup, skill: .advanced)
        )
        let drift = try #require(alerts.first { $0.kind == .offshoreDrift })
        #expect(drift.severity == .danger)
    }

    @Test("A measured offshore wind crushes the score, not just the banner")
    func measuredWindSuppressesScore() {
        let profile = UserProfile(sport: .surfing, skill: .beginner)
        let calm = conditions(modelKnots: 4, modelRelation: .offshore, measured: nil)
        let blowing = conditions(modelKnots: 4, modelRelation: .offshore, measured: measured(knots: 14))

        // A banner beside an 80 is an argument the banner loses, so the score has
        // to move with the measurement that raised the alert.
        #expect(MatchScoreEngine.score(for: blowing, profile: profile).value
                < MatchScoreEngine.score(for: calm, profile: profile).value)
    }
}

@Suite("Large surf hazard")
struct LargeSurfTests {
    private func conditions(heightMeters: Double) -> SpotConditions {
        SpotConditions.fixture(
            waveHeightMeters: heightMeters,
            periodSeconds: 10,
            windSpeedMPS: mps(knots: 4),
            windRelation: .sideShore
        )
    }

    @Test("Head-high surf warns a beginner but not an advanced surfer")
    func headHighWarnsBeginnerOnly() {
        let big = conditions(heightMeters: 1.2)

        let beginner = SafetyEngine.alerts(
            for: big, profile: UserProfile(sport: .surfing, skill: .beginner)
        )
        let advanced = SafetyEngine.alerts(
            for: big, profile: UserProfile(sport: .surfing, skill: .advanced)
        )

        #expect(beginner.contains { $0.kind == .largeSurf })
        #expect(!advanced.contains { $0.kind == .largeSurf })
    }

    @Test("Double-overhead is a danger for everyone")
    func doubleOverheadWarnsEveryone() throws {
        for skill in SkillLevel.allCases {
            let alerts = SafetyEngine.alerts(
                for: conditions(heightMeters: 3.0),
                profile: UserProfile(sport: .surfing, skill: skill)
            )
            let surf = try #require(alerts.first { $0.kind == .largeSurf }, "no alert for \(skill)")
            #expect(surf.severity == .danger)
        }
    }

    @Test("A knee-high summer day warns nobody")
    func smallSurfIsSilent() {
        let alerts = SafetyEngine.alerts(
            for: conditions(heightMeters: 0.3),
            profile: UserProfile(sport: .surfing, skill: .beginner)
        )
        #expect(alerts.isEmpty)
    }
}

@Suite("Alert severity ordering")
struct AlertSeverityTests {
    @Test("Danger outranks caution")
    func dangerOutranksCaution() {
        #expect(AlertSeverity.danger > AlertSeverity.caution)
        #expect([AlertSeverity.caution, .danger].max() == .danger)
    }
}
