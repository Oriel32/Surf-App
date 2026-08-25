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
