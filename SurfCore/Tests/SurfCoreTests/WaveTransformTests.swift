import Foundation
import Testing
@testable import SurfCore

@Suite("Linear wave theory")
struct WaveTheoryTests {
    @Test("Dispersion relation is satisfied by the solved wave number")
    func dispersionRelationHolds() {
        let period = 9.0
        let depth = 3.0
        let k = WaveTransform.waveNumber(periodSeconds: period, depthMeters: depth)

        let omega = 2 * Double.pi / period
        let lhs = omega * omega
        let rhs = WaveTransform.g * k * tanh(k * depth)

        // Newton must converge on an actual root, not merely terminate.
        #expect(abs(lhs - rhs) < 1e-6)
    }

    @Test("Shoaling amplifies a swell as it reaches the sandbar")
    func shoalingAmplifies() {
        // An 8 s swell in 2 m of water stands up roughly 20-25% taller than it
        // was offshore. This is why the open-sea number under-reports the face.
        let ks = WaveTransform.shoalingCoefficient(periodSeconds: 8, depthMeters: 2)
        #expect(ks > 1.15)
        #expect(ks < 1.30)
    }

    @Test("Shoaling is a no-op in deep water")
    func shoalingNeutralInDeepWater() {
        let ks = WaveTransform.shoalingCoefficient(periodSeconds: 8, depthMeters: 200)
        #expect(abs(ks - 1.0) < 0.01)
    }

    @Test("A longer-period swell feels the bottom sooner")
    func longerPeriodShoalsMore() {
        let short = WaveTransform.shoalingCoefficient(periodSeconds: 5, depthMeters: 3)
        let long = WaveTransform.shoalingCoefficient(periodSeconds: 14, depthMeters: 3)
        #expect(long > short)
    }

    @Test("Refraction is neutral for a swell arriving straight on")
    func refractionNeutralAtNormalIncidence() throws {
        let kr = try #require(
            WaveTransform.refractionCoefficient(periodSeconds: 8, depthMeters: 2, incidentAngleDegrees: 0)
        )
        #expect(abs(kr - 1.0) < 0.001)
    }

    @Test("An oblique swell loses height to refraction")
    func obliqueSwellLosesHeight() throws {
        let kr = try #require(
            WaveTransform.refractionCoefficient(periodSeconds: 8, depthMeters: 2, incidentAngleDegrees: 60)
        )
        #expect(kr < 1.0)
        #expect(kr > 0.0)
    }

    @Test("A swell from behind the shoreline cannot reach the beach")
    func swellFromBehindIsShadowed() {
        // The single most common way a naive forecast lies: reporting a big
        // south swell at a north-facing beach that physically cannot see it.
        #expect(
            WaveTransform.refractionCoefficient(
                periodSeconds: 8, depthMeters: 2, incidentAngleDegrees: 120
            ) == nil
        )
    }

    @Test("Breaking height is capped at 0.78 times the depth")
    func breakingLimit() {
        #expect(abs(WaveTransform.breakingHeightLimit(depthMeters: 2) - 1.56) < 1e-9)
    }
}

@Suite("Spot transformation")
struct SpotTransformTests {
    @Test("A sheltered beach receives less than an exposed one in the same swell")
    func shelteringReducesHeight() {
        let sample = RawMarineSample.fixture(waveHeightMeters: 1.5, wavePeriodSeconds: 9)
        let exposed = WaveTransform.transform(sample, at: .fixture(exposureCoefficient: 0.90))
        let bay = WaveTransform.transform(sample, at: .fixture(exposureCoefficient: 0.50))

        #expect(exposed.waveHeightMeters > bay.waveHeightMeters)
        // Haifa Bay takes roughly half of what Palmachim does — the whole point
        // of per-spot coefficients.
        #expect(bay.waveHeightMeters < exposed.waveHeightMeters * 0.7)
    }

    @Test("A storm swell is capped by the depth it breaks in")
    func stormIsDepthLimited() {
        let storm = RawMarineSample.fixture(waveHeightMeters: 5.0, wavePeriodSeconds: 12)
        let conditions = WaveTransform.transform(storm, at: .fixture(breakDepthMeters: 2.0))

        // No 5 m face on a 2 m sandbar, no matter what the model says offshore.
        #expect(conditions.waveHeightMeters <= WaveTransform.breakingHeightLimit(depthMeters: 2.0) + 1e-9)
    }

    @Test("The untransformed open-sea height is preserved for the detail view")
    func openSeaHeightIsKept() {
        let sample = RawMarineSample.fixture(waveHeightMeters: 1.4)
        let conditions = WaveTransform.transform(sample, at: .fixture())

        #expect(conditions.openSeaHeightMeters == 1.4)
        #expect(conditions.waveHeightMeters != conditions.openSeaHeightMeters)
    }

    @Test("Mediterranean output is never flagged synthetic")
    func mediterraneanIsNotSynthetic() {
        let conditions = WaveTransform.transform(.fixture(), at: .fixture())
        #expect(conditions.isSynthetic == false)
    }
}

@Suite("Gulf of Eilat")
struct EilatTests {
    @Test("Wave height is derived from local wind, not from the wave model")
    func heightComesFromWind() {
        // Global models do not resolve the gulf. A model claiming 2 m of swell
        // there must be ignored entirely.
        let bogusModelSwell = RawMarineSample.fixture(
            waveHeightMeters: 2.0,
            wavePeriodSeconds: 11,
            windSpeedMPS: mps(knots: 10)
        )
        let conditions = WaveTransform.transform(
            bogusModelSwell,
            at: .fixture(shorelineNormalDegrees: 200, basin: .gulfOfEilat)
        )

        // Hs = knots * 0.04 = 0.40 m, nothing like the model's 2 m.
        #expect(abs(conditions.waveHeightMeters - 0.40) < 0.01)
        #expect(conditions.isSynthetic)
    }

    @Test("Period follows the wind-chop formula")
    func periodComesFromWind() {
        let sample = RawMarineSample.fixture(windSpeedMPS: mps(knots: 20))
        let conditions = WaveTransform.transform(sample, at: .fixture(basin: .gulfOfEilat))

        // Tp = 3 + 0.15 * 20 = 6.0 s
        #expect(abs(conditions.periodSeconds - 6.0) < 0.02)
    }

    @Test("A windless gulf is flat")
    func windlessGulfIsFlat() {
        let sample = RawMarineSample.fixture(waveHeightMeters: 1.5, windSpeedMPS: 0)
        let conditions = WaveTransform.transform(sample, at: .fixture(basin: .gulfOfEilat))

        #expect(conditions.waveHeightMeters == 0)
        #expect(conditions.seaState == .flat)
    }
}

@Suite("Wind geometry")
struct WindRelationTests {
    @Test("An easterly is offshore on a west-facing beach")
    func easterlyIsOffshore() {
        let relation = Compass.windRelation(windFromDegrees: 90, shorelineNormalDegrees: 270)
        #expect(relation == .offshore)
        #expect(relation.blowsAwayFromShore)
    }

    @Test("A westerly is onshore on a west-facing beach")
    func westerlyIsOnshore() {
        #expect(Compass.windRelation(windFromDegrees: 270, shorelineNormalDegrees: 270) == .onshore)
    }

    @Test("A northerly is side-shore on a west-facing beach")
    func northerlyIsSideShore() {
        #expect(Compass.windRelation(windFromDegrees: 0, shorelineNormalDegrees: 270) == .sideShore)
    }

    @Test("Haifa Bay is classified against its own orientation, not the compass")
    func haifaBayUsesItsOwnGeometry() {
        // A north-westerly is onshore in Haifa Bay but side-shore in Tel Aviv.
        // A hardcoded "west is onshore" rule gets this wrong.
        #expect(Compass.windRelation(windFromDegrees: 300, shorelineNormalDegrees: 300) == .onshore)
        #expect(Compass.windRelation(windFromDegrees: 300, shorelineNormalDegrees: 270) != .onshore)
    }

    @Test("Angular distance wraps correctly across north")
    func angularDistanceWraps() {
        #expect(abs(Compass.angularDistance(350, 10) - 20) < 1e-9)
        #expect(abs(Compass.angularDistance(10, 350) - 20) < 1e-9)
        #expect(abs(Compass.angularDistance(0, 180) - 180) < 1e-9)
    }
}
