import Foundation

/// One wave train — swell or wind wave — as a model reports it.
public struct SwellComponent: Sendable, Equatable {
    public let heightMeters: Double
    public let periodSeconds: Double
    /// Direction the waves travel *from*, degrees true.
    public let directionDegrees: Double

    public init(heightMeters: Double, periodSeconds: Double, directionDegrees: Double) {
        self.heightMeters = heightMeters
        self.periodSeconds = periodSeconds
        self.directionDegrees = directionDegrees
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

    public let airTemperatureC: Double?
    public let seaSurfaceTemperatureC: Double?
    public let seaLevelMeters: Double?

    public init(
        timestamp: Date,
        waveHeightMeters: Double,
        wavePeriodSeconds: Double,
        waveDirectionDegrees: Double,
        primarySwell: SwellComponent? = nil,
        windWave: SwellComponent? = nil,
        windSpeedMPS: Double,
        windDirectionDegrees: Double,
        airTemperatureC: Double? = nil,
        seaSurfaceTemperatureC: Double? = nil,
        seaLevelMeters: Double? = nil
    ) {
        self.timestamp = timestamp
        self.waveHeightMeters = waveHeightMeters
        self.wavePeriodSeconds = wavePeriodSeconds
        self.waveDirectionDegrees = waveDirectionDegrees
        self.primarySwell = primarySwell
        self.windWave = windWave
        self.windSpeedMPS = windSpeedMPS
        self.windDirectionDegrees = windDirectionDegrees
        self.airTemperatureC = airTemperatureC
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.seaLevelMeters = seaLevelMeters
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
