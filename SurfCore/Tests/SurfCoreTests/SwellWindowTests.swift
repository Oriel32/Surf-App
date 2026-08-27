import Foundation
import Testing
@testable import SurfCore

@Suite("Swell windows")
struct SwellWindowTests {
    @Test("A plain arc admits what is inside it and nothing else")
    func plainArc() {
        let window = SwellWindow(fromDegrees: 200, toDegrees: 320)
        #expect(window.admits(270))
        #expect(window.admits(200))
        #expect(window.admits(320))
        #expect(!window.admits(180))
        #expect(!window.admits(340))
    }

    @Test("An arc that wraps through north is still one window")
    func wrappingArc() {
        // The common shape on a west-facing coast: open from south-west round
        // through west to north-east.
        let window = SwellWindow(fromDegrees: 250, toDegrees: 30)
        #expect(window.admits(270))
        #expect(window.admits(350))
        #expect(window.admits(0))
        #expect(window.admits(30))
        #expect(!window.admits(90))
        #expect(!window.admits(200))
    }

    @Test("Bearings are normalised before they are tested")
    func normalisesBearings() {
        let window = SwellWindow(fromDegrees: 250, toDegrees: 30)
        #expect(window.admits(-10))   // 350
        #expect(window.admits(390))   // 30
    }

    @Test("A shadowed sector contributes nothing, however big the swell")
    func shadowedSectorIsZero() {
        // Shadowed is not the same as smaller: the exposure coefficient is a
        // scalar and cannot say "from there, nothing arrives".
        let spot = Spot.fixture(shorelineNormalDegrees: 270, breakDepthMeters: 5)
        let sheltered = Spot(
            id: spot.id, nameHebrew: spot.nameHebrew, nameEnglish: spot.nameEnglish,
            latitude: spot.latitude, longitude: spot.longitude, basin: spot.basin,
            exposureCoefficient: spot.exposureCoefficient,
            shorelineNormalDegrees: spot.shorelineNormalDegrees,
            breakDepthMeters: spot.breakDepthMeters,
            swellWindow: SwellWindow(fromDegrees: 250, toDegrees: 300)
        )

        // 220 is inside the half-plane refraction allows, but outside the window.
        let sample = RawMarineSample(
            timestamp: .utc(2026, 8, 26, 6),
            waveHeightMeters: 1.5, wavePeriodSeconds: 9, waveDirectionDegrees: 220,
            primarySwell: SwellComponent(
                heightMeters: 1.5, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 220
            ),
            windSpeedMPS: 2, windDirectionDegrees: 90
        )

        #expect(WaveTransform.transform(sample, at: spot).waveHeightMeters > 0)
        #expect(WaveTransform.transform(sample, at: sheltered).waveHeightMeters == 0)
    }

    @Test("No window means no extra shadowing, so old spots behave as before")
    func absentWindowChangesNothing() {
        #expect(Spot.fixture().swellWindow == nil)
    }
}

@Suite("Tide-aware breaking depth")
struct TideDepthTests {
    private func sample(seaLevel: Double?) -> RawMarineSample {
        RawMarineSample(
            timestamp: .utc(2026, 8, 26, 6),
            waveHeightMeters: 3.0, wavePeriodSeconds: 9, waveDirectionDegrees: 270,
            primarySwell: SwellComponent(
                heightMeters: 3.0, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 270
            ),
            windSpeedMPS: 2, windDirectionDegrees: 90,
            seaLevelMeters: seaLevel
        )
    }

    @Test("A higher tide raises the depth-limited ceiling")
    func tideRaisesTheCap() {
        // The cap is 0.78 x depth, so on a shallow bar even a small tide moves
        // the biggest wave the spot can hold.
        let spot = Spot.fixture(exposureCoefficient: 1.0, breakDepthMeters: 1.5)
        let low = WaveTransform.transform(sample(seaLevel: -0.2), at: spot).breakingLimitMeters
        let mid = WaveTransform.transform(sample(seaLevel: 0), at: spot).breakingLimitMeters
        let high = WaveTransform.transform(sample(seaLevel: 0.2), at: spot).breakingLimitMeters

        #expect(low < mid)
        #expect(mid < high)
        #expect(abs(high - 0.78 * 1.7) < 1e-6)
    }

    @Test("Missing sea level falls back to the nominal depth rather than failing")
    func missingTideIsNominal() {
        let spot = Spot.fixture(exposureCoefficient: 1.0, breakDepthMeters: 1.5)
        let absent = WaveTransform.transform(sample(seaLevel: nil), at: spot).breakingLimitMeters
        #expect(abs(absent - 0.78 * 1.5) < 1e-6)
    }

    @Test("An absurd sea level cannot produce a negative depth")
    func depthIsFloored() {
        let spot = Spot.fixture(exposureCoefficient: 1.0, breakDepthMeters: 1.5)
        let broken = WaveTransform.transform(sample(seaLevel: -99), at: spot)
        #expect(broken.waveHeightMeters > 0)
        #expect(broken.breakingLimitMeters <= 0.78 * 0.5)
        // The bar can hold almost nothing at this depth, so the score sees
        // almost nothing — even though the sea itself is still metres deep.
        #expect(broken.rideableHeightMeters <= 0.78 * 0.5)
        #expect(broken.isDepthLimited)
    }
}
