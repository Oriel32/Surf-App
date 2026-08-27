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

    @Test("A storm swell is flagged depth-limited, and the score is what gets clipped")
    func stormIsDepthLimited() {
        let storm = RawMarineSample.fixture(waveHeightMeters: 5.0, wavePeriodSeconds: 12)
        let conditions = WaveTransform.transform(storm, at: .fixture(breakDepthMeters: 2.0))
        let limit = WaveTransform.breakingHeightLimit(depthMeters: 2.0)

        // The reported height is no longer clipped to the bar: clipping it made
        // every big day at a shallow spot report the same ceiling, which cost
        // the week its shape. See calibration/bat-yam-comparison.md.
        #expect(conditions.waveHeightMeters > limit)
        #expect(conditions.isDepthLimited)

        // The constraint is enforced where it belongs — on what the score sees.
        #expect(conditions.rideableHeightMeters <= limit + 1e-9)
        #expect(conditions.rideableEnergyKilowattsPerMetre < conditions.energyKilowattsPerMetre)
    }

    @Test("Two different big days stay different instead of both pinning to the ceiling")
    func bigDaysRemainDistinguishable() {
        // The Bat Yam regression, hermetic. On 2026-08-27 the 29th and 30th of
        // August both reported exactly 1.60 m from open-sea inputs of 1.76 m and
        // 1.94 m, while GoSurf separated the same days as 90 cm and 200 cm. A
        // week that cannot rank its own days sends people out on the wrong one.
        let spot = Spot.fixture(id: "bat-yam", exposureCoefficient: 0.85, breakDepthMeters: 2.0)
        let smaller = WaveTransform.transform(.fixture(waveHeightMeters: 1.76), at: spot)
        let bigger = WaveTransform.transform(.fixture(waveHeightMeters: 1.94), at: spot)

        #expect(smaller.waveHeightMeters < bigger.waveHeightMeters)
        #expect(bigger.waveHeightMeters - smaller.waveHeightMeters > 0.1)
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

@Suite("Transformation trace")
struct TransformTraceTests {
    /// The trace is a calibration instrument, and an instrument that disagrees
    /// with the thing it measures is worse than no instrument: it sends you off
    /// tuning a coefficient that was never the problem. Every assertion in this
    /// suite exists to keep the trace and the shipped transform the same code.
    @Test("The trace reports exactly what the transform returned")
    func traceMatchesTransform() {
        let sample = RawMarineSample.fixture(
            waveHeightMeters: 1.1,
            wavePeriodSeconds: 8,
            waveDirectionDegrees: 285
        )
        let spot = Spot.fixture(exposureCoefficient: 0.85, breakDepthMeters: 2.0)

        let (conditions, trace) = WaveTransform.explain(sample, at: spot)

        #expect(conditions == WaveTransform.transform(sample, at: spot))
        #expect(trace.significantMeters == conditions.waveHeightMeters)
        #expect(trace.periodSeconds == conditions.periodSeconds)
        #expect(trace.band == conditions.band)
        #expect(trace.spotID == spot.id)
    }

    @Test("Each stage multiplies through to the height the pipeline reports")
    func stagesMultiplyThroughToTheAnswer() throws {
        // The whole point of the trace: multiplying the printed factors by hand
        // must land on the printed answer. If it does not, one of the stages is
        // unreported and the trace is hiding the culprit.
        let sample = RawMarineSample.fixture(
            waveHeightMeters: 0.9,
            wavePeriodSeconds: 7,
            waveDirectionDegrees: 280
        )
        let (_, trace) = WaveTransform.explain(sample, at: .fixture(exposureCoefficient: 0.85))

        let train = try #require(trace.trains.first)
        let exposure = try #require(train.afterExposureMeters)
        let refraction = try #require(train.refractionCoefficient)
        let shoaling = try #require(train.shoalingCoefficient)

        #expect(abs(exposure - train.openSeaHeightMeters * train.exposureCoefficient) < 1e-9)
        #expect(abs(train.heightMeters - exposure * refraction * shoaling) < 1e-9)
        #expect(abs(trace.combinedMeters - train.heightMeters) < 1e-9)
        #expect(trace.capApplied == false)
        #expect(abs(trace.significantMeters - train.heightMeters) < 1e-9)
    }

    @Test("The trace reports the bar being exceeded without pretending it clipped the sea")
    func capIsReportedWhenExceeded() {
        // Without this flag a depth-limited day looks like an ordinary one, and
        // you tune the coefficient for hours before noticing the bar was
        // deciding the score all along.
        let storm = RawMarineSample.fixture(waveHeightMeters: 5.0, wavePeriodSeconds: 12)
        let (conditions, trace) = WaveTransform.explain(storm, at: .fixture(breakDepthMeters: 2.0))

        #expect(trace.capApplied)
        #expect(abs(trace.breakingLimitMeters - 1.56) < 1e-9)
        #expect(trace.combinedMeters > trace.breakingLimitMeters)
        // Reported as measured, not clipped to the limit.
        #expect(abs(trace.significantMeters - trace.combinedMeters) < 1e-9)
        #expect(conditions.isDepthLimited)
    }

    @Test("A mean-period fallback is flagged, not silently passed off as a peak period")
    func meanPeriodFallbackIsVisible() throws {
        // Tm runs about 0.78 of Tp. Unflagged, that is a 22% period error that
        // looks identical to a real reading — and period drives the score.
        func sample(with swell: SwellComponent) -> RawMarineSample {
            RawMarineSample(
                timestamp: .utc(2026, 8, 25, 6),
                waveHeightMeters: 0.8, wavePeriodSeconds: 6, waveDirectionDegrees: 280,
                primarySwell: swell,
                windSpeedMPS: 3, windDirectionDegrees: 90
            )
        }

        let withPeak = sample(with: SwellComponent(
            heightMeters: 0.8, periodSeconds: 6, peakPeriodSeconds: 8, directionDegrees: 280
        ))
        let withoutPeak = sample(with: SwellComponent(
            heightMeters: 0.8, periodSeconds: 6, directionDegrees: 280
        ))

        let peakTrain = try #require(WaveTransform.explain(withPeak, at: .fixture()).trace.trains.first)
        #expect(peakTrain.periodIsPeak)
        #expect(peakTrain.periodSeconds == 8)

        let meanTrain = try #require(WaveTransform.explain(withoutPeak, at: .fixture()).trace.trains.first)
        #expect(meanTrain.periodIsPeak == false)
        #expect(meanTrain.periodSeconds == 6)
    }

    @Test("A shadowed train says why it delivered nothing")
    func shadowedTrainNamesItsCause() throws {
        // A south swell at a west-facing beach: zero height is the right answer,
        // and "shadowed" is a different diagnosis from "the coefficient is harsh".
        let southSwell = RawMarineSample.fixture(
            waveHeightMeters: 1.2,
            waveDirectionDegrees: 90  // from the east, behind the beach
        )
        let (_, trace) = WaveTransform.explain(southSwell, at: .fixture(shorelineNormalDegrees: 270))

        let train = try #require(trace.trains.first)
        #expect(train.shadowing == .behindTheShoreline)
        #expect(train.heightMeters == 0)
        #expect(train.shoalingCoefficient == nil)
    }

    @Test("The band is chosen from the number the user reads, not from the sets")
    func bandAgreesWithTheDisplayedNumber() {
        // The contradiction this replaced: the app printed 0.48 m beside
        // "waist to chest", because the band had been chosen from 0.48 × 1.27.
        // The sets are still shown — as the top of the displayed range.
        let (conditions, trace) = WaveTransform.explain(
            .fixture(waveHeightMeters: 1.0, wavePeriodSeconds: 8),
            at: .fixture()
        )

        #expect(trace.bandDefiningMeters == trace.significantMeters)
        #expect(trace.band == WaveBand.band(
            forHeightMeters: trace.significantMeters,
            periodSeconds: trace.periodSeconds,
            seaState: conditions.seaState
        ))
        #expect(abs(trace.setMeters - trace.significantMeters * 1.27) < 1e-9)
    }

    @Test("Both partitions of a mixed sea are traced and labelled")
    func mixedSeaTracesEveryTrain() {
        let mixed = RawMarineSample(
            timestamp: .utc(2026, 8, 25, 6),
            waveHeightMeters: 0.78, wavePeriodSeconds: 6, waveDirectionDegrees: 270,
            primarySwell: SwellComponent(
                heightMeters: 0.6, periodSeconds: 7, peakPeriodSeconds: 9, directionDegrees: 280
            ),
            windWave: SwellComponent(heightMeters: 0.5, periodSeconds: 4, directionDegrees: 250),
            windSpeedMPS: 3, windDirectionDegrees: 90
        )
        let (_, trace) = WaveTransform.explain(mixed, at: .fixture())

        #expect(trace.trains.map(\.label) == [.swell, .windWave])

        // Quadrature, and the reported period belongs to whichever train is tallest.
        let quadrature = trace.trains
            .reduce(0) { $0 + $1.heightMeters * $1.heightMeters }
            .squareRoot()
        #expect(abs(trace.combinedMeters - quadrature) < 1e-9)

        let tallest = trace.trains.max { $0.heightMeters < $1.heightMeters }
        #expect(trace.dominantTrainLabel == tallest?.label)
    }

    @Test("The Eilat trace declares itself synthetic rather than showing a physics it never ran")
    func eilatTraceIsMarkedSynthetic() {
        let (_, trace) = WaveTransform.explain(
            .fixture(waveHeightMeters: 2.0, windSpeedMPS: mps(knots: 10)),
            at: .fixture(basin: .gulfOfEilat)
        )

        #expect(trace.isSynthetic)
        #expect(trace.trains.isEmpty)
        #expect(abs(trace.significantMeters - 0.40) < 0.01)
    }

    @Test("The report renders every stage without crashing on a shadowed or capped sea")
    func reportRendersEveryPath() {
        let cases: [(RawMarineSample, Spot)] = [
            (.fixture(), .fixture()),
            (.fixture(waveHeightMeters: 5.0), .fixture(breakDepthMeters: 1.5)),
            (.fixture(waveDirectionDegrees: 90), .fixture(shorelineNormalDegrees: 270)),
            (.fixture(windSpeedMPS: mps(knots: 12)), .fixture(basin: .gulfOfEilat))
        ]

        for (sample, spot) in cases {
            let lines = WaveTransform.explain(sample, at: spot).trace.report()
            #expect(lines.isEmpty == false)
            #expect(lines.contains { $0.hasPrefix("DISPLAYED") })
            #expect(lines.contains { $0.hasPrefix("BAND") })
        }
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
