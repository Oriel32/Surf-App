import Foundation

/// One wave train — swell or wind wave — as a model reports it.
///
/// ## Mean period is not peak period
/// Models report both and they are different physical quantities: `Tm` is the
/// mean of all periods present, `Tp` the period of the most energetic band.
/// The ratio runs about 0.75–0.85, and measured against this coast it is 0.78.
///
/// **Every buoy and every surf forecast quotes Tp**, so it is the only one that
/// can be compared against ground truth or against another app. Feeding Tm into
/// thresholds written for Tp under-reads the sea by roughly a quarter — enough
/// to score three quarters of the hours here as wind slop when almost none are.
public struct SwellComponent: Sendable, Equatable {
    public let heightMeters: Double
    /// Mean period, Tm. Open-Meteo's `*_wave_period`.
    public let periodSeconds: Double
    /// Peak period, Tp. Open-Meteo's `*_wave_peak_period`.
    ///
    /// Optional because the combined-sea fallback below has no peak variable to
    /// draw on; `surfPeriodSeconds` degrades to the mean when it is missing.
    public let peakPeriodSeconds: Double?
    /// Direction the waves travel *from*, degrees true.
    public let directionDegrees: Double

    public init(
        heightMeters: Double,
        periodSeconds: Double,
        peakPeriodSeconds: Double? = nil,
        directionDegrees: Double
    ) {
        self.heightMeters = heightMeters
        self.periodSeconds = periodSeconds
        self.peakPeriodSeconds = peakPeriodSeconds
        self.directionDegrees = directionDegrees
    }

    /// The period that reaches users and the score. Prefer Tp; fall back to Tm
    /// only when the source did not supply one.
    public var surfPeriodSeconds: Double {
        peakPeriodSeconds ?? periodSeconds
    }

    /// Deep-water wave power, kW/m: `P = (rho g^2 / 64 pi) H^2 T`, which for
    /// seawater is very close to `0.5 H^2 T`.
    ///
    /// This is the quantity Surfline and Magicseaweed lead with, and the reason
    /// they do: 1 m at 12 s carries nearly two and a half times the punch of
    /// 1 m at 5 s, and height alone cannot say so.
    public var energyKilowattsPerMetre: Double {
        0.5 * heightMeters * heightMeters * surfPeriodSeconds
    }
}

/// A single hour of open-sea model output, normalised to SI.
///
/// This is deliberately *raw*: it is what the model says about deep water
/// offshore, before any spot transformation. It must never reach a view.
/// `WaveTransform` converts it into `SpotConditions`, which is the type the UI
/// is allowed to see.
public struct RawMarineSample: Sendable, Equatable {
    public let timestamp: Date

    /// Significant wave height of the combined sea, metres.
    public let waveHeightMeters: Double
    /// Peak period of the combined sea, seconds.
    public let wavePeriodSeconds: Double
    /// Direction the combined sea arrives from, degrees true.
    public let waveDirectionDegrees: Double

    /// Groundswell, reported separately where the source supports it.
    /// A 0.7 m groundswell and a 0.7 m wind chop are the same number and a
    /// completely different product for the user, so these never get merged.
    public let primarySwell: SwellComponent?
    public let windWave: SwellComponent?

    public let windSpeedMPS: Double
    /// Direction the wind blows *from*, degrees true.
    public let windDirectionDegrees: Double

    /// Gust speed, m/s. Absent from sources that do not report it.
    ///
    /// The gust matters more than the mean for how a sea *feels*. A 9-knot mean
    /// gusting to 16 is a shifty, textured session and a 9-knot mean gusting to
    /// 11 is a clean one, and the mean alone cannot tell them apart.
    public let windGustMPS: Double?

    public let airTemperatureC: Double?
    public let seaSurfaceTemperatureC: Double?
    public let seaLevelMeters: Double?

    /// Whether this hour falls between sunrise and sunset at the spot.
    ///
    /// Decided at ingest, from the provider's own sunrise and sunset, because
    /// that is where the date and the coordinates are both to hand. A forecast
    /// that reports its best hour at 03:00 is not wrong so much as useless, and
    /// this is what lets the window search say so.
    ///
    /// Defaults to `true` for sources that do not supply it — being permissive
    /// keeps a source without daylight data working exactly as it did before.
    public let isDaylight: Bool

    public init(
        timestamp: Date,
        waveHeightMeters: Double,
        wavePeriodSeconds: Double,
        waveDirectionDegrees: Double,
        primarySwell: SwellComponent? = nil,
        windWave: SwellComponent? = nil,
        windSpeedMPS: Double,
        windDirectionDegrees: Double,
        windGustMPS: Double? = nil,
        airTemperatureC: Double? = nil,
        seaSurfaceTemperatureC: Double? = nil,
        seaLevelMeters: Double? = nil,
        isDaylight: Bool = true
    ) {
        self.timestamp = timestamp
        self.waveHeightMeters = waveHeightMeters
        self.wavePeriodSeconds = wavePeriodSeconds
        self.waveDirectionDegrees = waveDirectionDegrees
        self.primarySwell = primarySwell
        self.windWave = windWave
        self.windSpeedMPS = windSpeedMPS
        self.windDirectionDegrees = windDirectionDegrees
        self.windGustMPS = windGustMPS
        self.airTemperatureC = airTemperatureC
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.seaLevelMeters = seaLevelMeters
        self.isDaylight = isDaylight
    }

    /// The independent wave trains present in this hour.
    ///
    /// A partitioned sea is two or more trains arriving on different bearings
    /// with different periods, and each has to be shoaled and refracted on its
    /// own geometry — a 9 s groundswell from the west and a 3 s chop from the
    /// north-west do not share a physics. Falls back to the combined sea when
    /// the source does not partition, which is the only case where treating the
    /// sea as one train is correct.
    public var partitions: [SwellComponent] {
        let separated = [primarySwell, windWave]
            .compactMap { $0 }
            .filter { $0.heightMeters > 0 }
        guard separated.isEmpty else { return separated }
        return [SwellComponent(
            heightMeters: waveHeightMeters,
            periodSeconds: wavePeriodSeconds,
            directionDegrees: waveDirectionDegrees
        )]
    }

    /// The wave train that actually matters for surfing: groundswell when the
    /// source separates it out, otherwise the combined sea.
    public var dominantTrain: SwellComponent {
        primarySwell ?? SwellComponent(
            heightMeters: waveHeightMeters,
            periodSeconds: wavePeriodSeconds,
            directionDegrees: waveDirectionDegrees
        )
    }
}

/// A real measurement from a real buoy, with the timestamp that makes it
/// trustworthy or worthless.
public struct BuoyObservation: Sendable, Equatable {
    public let stationID: String
    public let observedAt: Date
    public let significantWaveHeightMeters: Double
    public let peakPeriodSeconds: Double
    public let maximumWaveHeightMeters: Double?

    public init(
        stationID: String,
        observedAt: Date,
        significantWaveHeightMeters: Double,
        peakPeriodSeconds: Double,
        maximumWaveHeightMeters: Double? = nil
    ) {
        self.stationID = stationID
        self.observedAt = observedAt
        self.significantWaveHeightMeters = significantWaveHeightMeters
        self.peakPeriodSeconds = peakPeriodSeconds
        self.maximumWaveHeightMeters = maximumWaveHeightMeters
    }

    public func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(observedAt)
    }

    /// A 200 response from ISRAMAR is not evidence of fresh data — the Shikmona
    /// endpoint has served a January reading with HTTP 200 for months. Freshness
    /// is decided here, from the payload's own timestamp, and nowhere else.
    public func isFresh(asOf now: Date = Date(), maxAge: TimeInterval = 3 * 3600) -> Bool {
        let elapsed = age(asOf: now)
        return elapsed >= 0 && elapsed <= maxAge
    }
}

/// Per-parameter disagreement between forecast models, for one hour.
///
/// Confidence is measured, never asserted: it is the spread between independent
/// models, which is why it needs a source that reports them separately.
public struct ModelSpread: Sendable, Equatable {
    public let timestamp: Date
    /// Wave height in metres, keyed by model identifier (`noaa`, `icon`, ...).
    public let waveHeightByModel: [String: Double]

    public init(timestamp: Date, waveHeightByModel: [String: Double]) {
        self.timestamp = timestamp
        self.waveHeightByModel = waveHeightByModel
    }

    /// 0...1, where 1 is unanimous agreement.
    ///
    /// Uses coefficient of variation so the metric stays meaningful across
    /// heights — 0.2 m of disagreement is noise in a 3 m storm and a total
    /// contradiction in a 0.3 m summer sea.
    public var confidence: Double {
        let values = Array(waveHeightByModel.values)
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0.01 else { return 1 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let coefficientOfVariation = variance.squareRoot() / mean
        return max(0, min(1, 1 - coefficientOfVariation * 2))
    }
}
