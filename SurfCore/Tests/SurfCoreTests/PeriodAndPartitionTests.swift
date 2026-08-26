import Foundation
import Testing
@testable import SurfCore

@Suite("Peak period, not mean period")
struct PeakPeriodTests {
    @Test("The surf period is the peak, never the mean, when both are present")
    func prefersPeakPeriod() {
        // Measured against this coast the ratio is 0.78 - Tm 4.8 s where Tp is
        // 6.3 s. Reading the mean under-calls the sea by roughly a quarter.
        let train = SwellComponent(
            heightMeters: 0.6, periodSeconds: 4.8, peakPeriodSeconds: 6.3, directionDegrees: 270
        )
        #expect(train.surfPeriodSeconds == 6.3)
        #expect(train.periodSeconds == 4.8)
    }

    @Test("A source with no peak period degrades to the mean rather than dropping the train")
    func fallsBackToMean() {
        let train = SwellComponent(heightMeters: 0.6, periodSeconds: 5.0, directionDegrees: 270)
        #expect(train.surfPeriodSeconds == 5.0)
    }

    @Test("The transform reports the peak period, so it is comparable to a buoy")
    func transformReportsPeak() {
        // Buoys report Tp. A forecast that reports Tm cannot be checked against
        // one, which is how this went unnoticed.
        let sample = RawMarineSample(
            timestamp: .utc(2026, 8, 26, 17),
            waveHeightMeters: 0.56, wavePeriodSeconds: 5.9, waveDirectionDegrees: 270,
            primarySwell: SwellComponent(
                heightMeters: 0.56, periodSeconds: 5.0, peakPeriodSeconds: 6.3, directionDegrees: 270
            ),
            windSpeedMPS: 3, windDirectionDegrees: 270
        )
        let conditions = WaveTransform.transform(sample, at: .fixture())
        #expect(conditions.periodSeconds == 6.3)
    }

    @Test("Reading the mean would have scored most of this basin as wind slop")
    func meanPeriodMisclassifiesTheBasin() {
        // The research calls anything under 5 s wind slop. The median mean
        // period here is 4.8 s and the median peak is 6.3 s, so the choice of
        // variable decides whether a normal day is surfable or garbage.
        let tuning = ScoreTuning.surfing
        #expect(tuning.period.value(4.8) < 0.5)
        #expect(tuning.period.value(6.3) > 0.75)
    }
}

@Suite("Partitioned seas")
struct PartitionTests {
    private func sample(
        swell: SwellComponent?, wind: SwellComponent?, combined: Double = 1.0
    ) -> RawMarineSample {
        RawMarineSample(
            timestamp: .utc(2026, 8, 26, 6),
            waveHeightMeters: combined, wavePeriodSeconds: 5, waveDirectionDegrees: 270,
            primarySwell: swell, windWave: wind,
            windSpeedMPS: 3, windDirectionDegrees: 90
        )
    }

    @Test("Separate trains are kept separate")
    func partitionsAreSeparate() {
        let s = sample(
            swell: SwellComponent(heightMeters: 0.8, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 270),
            wind: SwellComponent(heightMeters: 0.4, periodSeconds: 3, peakPeriodSeconds: 3.5, directionDegrees: 300)
        )
        #expect(s.partitions.count == 2)
    }

    @Test("A source that does not partition falls back to the combined sea")
    func fallsBackToCombined() {
        let s = sample(swell: nil, wind: nil, combined: 1.2)
        #expect(s.partitions.count == 1)
        #expect(s.partitions[0].heightMeters == 1.2)
    }

    @Test("Zero-height partitions are dropped rather than transformed")
    func dropsEmptyTrains() {
        // Flat-calm wind wave is reported as 0.0, not as absent.
        let s = sample(
            swell: SwellComponent(heightMeters: 0.56, periodSeconds: 5, peakPeriodSeconds: 6.3, directionDegrees: 270),
            wind: SwellComponent(heightMeters: 0, periodSeconds: 1.5, peakPeriodSeconds: 1.5, directionDegrees: 300)
        )
        #expect(s.partitions.count == 1)
        #expect(s.partitions[0].peakPeriodSeconds == 6.3)
    }

    @Test("The reported period is the dominant train's, not a blend of the two")
    func reportsDominantPeriod() {
        // Averaging a 9 s groundswell with a 3 s chop describes neither.
        let s = sample(
            swell: SwellComponent(heightMeters: 1.0, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 270),
            wind: SwellComponent(heightMeters: 0.3, periodSeconds: 3, peakPeriodSeconds: 3.5, directionDegrees: 270)
        )
        let c = WaveTransform.transform(s, at: .fixture(breakDepthMeters: 5))
        #expect(c.periodSeconds == 9)
    }

    @Test("When chop dominates, the chop's period is what gets reported")
    func chopCanDominate() {
        let s = sample(
            swell: SwellComponent(heightMeters: 0.2, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 270),
            wind: SwellComponent(heightMeters: 0.9, periodSeconds: 3, peakPeriodSeconds: 3.5, directionDegrees: 270)
        )
        let c = WaveTransform.transform(s, at: .fixture(breakDepthMeters: 5))
        #expect(c.periodSeconds == 3.5)
    }

    @Test("Trains add in energy, so heights add in quadrature and never linearly")
    func heightsAddInQuadrature() {
        // Two equal 0.5 m trains make 0.71 m, not 1.0 m. Adding linearly would
        // double-count a sea that is really one train with a ripple on it.
        let equal = SwellComponent(heightMeters: 0.5, periodSeconds: 6, peakPeriodSeconds: 6, directionDegrees: 270)
        let s = sample(swell: equal, wind: equal)
        let spot = Spot.fixture(exposureCoefficient: 1.0, breakDepthMeters: 40)
        let c = WaveTransform.transform(s, at: spot)

        let single = WaveTransform.transform(sample(swell: equal, wind: nil), at: spot)
        #expect(c.waveHeightMeters > single.waveHeightMeters)
        #expect(c.waveHeightMeters < single.waveHeightMeters * 2)
        #expect(abs(c.waveHeightMeters - single.waveHeightMeters * 2.0.squareRoot()) < 1e-9)
    }

    @Test("A shadowed train contributes nothing, but its partner still does")
    func shadowedTrainDropsOut() {
        // A south swell at a west-facing beach is blocked by the land; a
        // west swell at the same beach is not.
        let blocked = SwellComponent(heightMeters: 1.0, periodSeconds: 8, peakPeriodSeconds: 9, directionDegrees: 90)
        let arriving = SwellComponent(heightMeters: 0.4, periodSeconds: 5, peakPeriodSeconds: 6, directionDegrees: 270)
        let spot = Spot.fixture(shorelineNormalDegrees: 270, breakDepthMeters: 5)

        let both = WaveTransform.transform(sample(swell: blocked, wind: arriving), at: spot)
        let onlyBlocked = WaveTransform.transform(sample(swell: blocked, wind: nil), at: spot)

        #expect(onlyBlocked.waveHeightMeters == 0)
        #expect(both.waveHeightMeters > 0)
        #expect(both.periodSeconds == 6)
    }
}

@Suite("Wave energy")
struct WaveEnergyTests {
    @Test("Energy goes as height squared times period")
    func energyFormula() {
        // The reason Surfline and Magicseaweed lead with energy: same height,
        // very different wave.
        let short = SwellComponent(heightMeters: 1.0, periodSeconds: 5, peakPeriodSeconds: 5, directionDegrees: 270)
        let long = SwellComponent(heightMeters: 1.0, periodSeconds: 12, peakPeriodSeconds: 12, directionDegrees: 270)
        #expect(abs(short.energyKilowattsPerMetre - 2.5) < 1e-9)
        #expect(abs(long.energyKilowattsPerMetre - 6.0) < 1e-9)
        #expect(long.energyKilowattsPerMetre > short.energyKilowattsPerMetre * 2)
    }

    @Test("Doubling the height quadruples the energy")
    func heightDominatesEnergy() {
        let small = SwellComponent(heightMeters: 0.5, periodSeconds: 8, peakPeriodSeconds: 8, directionDegrees: 270)
        let big = SwellComponent(heightMeters: 1.0, periodSeconds: 8, peakPeriodSeconds: 8, directionDegrees: 270)
        #expect(abs(big.energyKilowattsPerMetre - small.energyKilowattsPerMetre * 4) < 1e-9)
    }

    @Test("Energy uses the peak period, like the rest of the pipeline")
    func energyUsesPeak() {
        let train = SwellComponent(heightMeters: 1.0, periodSeconds: 4.8, peakPeriodSeconds: 6.3, directionDegrees: 270)
        #expect(abs(train.energyKilowattsPerMetre - 0.5 * 6.3) < 1e-9)
    }
}
