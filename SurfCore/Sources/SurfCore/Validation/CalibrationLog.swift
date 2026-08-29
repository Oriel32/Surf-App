import Foundation

/// One forecast checked against one real measurement.
///
/// ## Why this exists
/// The transformation engine is the highest-value code in this project and it
/// has never been checked against reality. Every test it has asserts it agrees
/// with hand-computed values from its own formulas — that is self-consistency,
/// which is necessary and says nothing about accuracy.
///
/// The smoke test has been fetching a forecast and a buoy reading side by side
/// since Phase 1, printing the difference, and throwing it away. Keeping them
/// turns a one-off eyeball check into a series that can actually be measured,
/// and lets the coefficients be tuned from data rather than from the round
/// numbers in the spec.
public struct CalibrationRecord: Sendable, Codable, Equatable {
    public let recordedAt: Date
    public let spotID: String
    public let stationID: String
    public let observedAt: Date

    /// The model's **open-sea** height for the observed hour.
    ///
    /// Deliberately not the transformed beach height: the buoy sits offshore,
    /// so comparing it against the beach value would flatter the transform by
    /// measuring it against something it never claimed to predict.
    public let modelOpenSeaHeightMeters: Double

    /// The model's peak period. Comparable to the buoy only because the ingest
    /// layer now reads `*_peak_period` rather than the mean.
    public let modelPeriodSeconds: Double

    /// The model's **swell partition** for the same hour, where the source
    /// separated it.
    ///
    /// Logged beside the combined height because the two answer different
    /// questions and only one of them is comparable to this buoy. On 2026-08-29
    /// the smoke test reported `model 1.10 m vs buoy 0.64 m — DISAGREE`, a
    /// +0.46 m error that looks like a badly miscalibrated model. Pulling
    /// Open-Meteo at the buoy's own coordinates for the same hour gave a
    /// combined 1.08 m and a **swell partition of 0.66 m** against the buoy's
    /// 0.64 m: the swell channel was right to 2 cm and the entire discrepancy
    /// was wind sea.
    ///
    /// Without this field the log accumulates that gap as a height bias, and
    /// `suggestedHeightCorrection` would eventually propose shrinking every
    /// spot's exposure coefficient to cancel an error the transform never made.
    /// A definition mismatch must not be tuned away as if it were a physics one.
    ///
    /// `nil` for records written before this was captured, and for any source
    /// that does not partition.
    public let modelSwellHeightMeters: Double?
    public let modelSwellPeriodSeconds: Double?

    public let buoyHeightMeters: Double
    public let buoyPeakPeriodSeconds: Double

    public init(
        recordedAt: Date,
        spotID: String,
        stationID: String,
        observedAt: Date,
        modelOpenSeaHeightMeters: Double,
        modelPeriodSeconds: Double,
        modelSwellHeightMeters: Double? = nil,
        modelSwellPeriodSeconds: Double? = nil,
        buoyHeightMeters: Double,
        buoyPeakPeriodSeconds: Double
    ) {
        self.recordedAt = recordedAt
        self.spotID = spotID
        self.stationID = stationID
        self.observedAt = observedAt
        self.modelOpenSeaHeightMeters = modelOpenSeaHeightMeters
        self.modelPeriodSeconds = modelPeriodSeconds
        self.modelSwellHeightMeters = modelSwellHeightMeters
        self.modelSwellPeriodSeconds = modelSwellPeriodSeconds
        self.buoyHeightMeters = buoyHeightMeters
        self.buoyPeakPeriodSeconds = buoyPeakPeriodSeconds
    }

    /// Signed. Positive means the model runs bigger than the sea.
    public var heightErrorMeters: Double {
        modelOpenSeaHeightMeters - buoyHeightMeters
    }

    /// The same error measured against the swell partition instead of the
    /// combined sea. `nil` where the partition was not captured.
    ///
    /// This is the number that should drive any coefficient change: it compares
    /// like with like.
    public var swellHeightErrorMeters: Double? {
        modelSwellHeightMeters.map { $0 - buoyHeightMeters }
    }

    public var periodErrorSeconds: Double {
        modelPeriodSeconds - buoyPeakPeriodSeconds
    }
}

/// Bias and spread over a set of records.
///
/// Both matter and they say different things. **Bias** is the signed mean: a
/// model that reads 0.2 m high every single time has a large bias and is easy
/// to correct. **RMSE** is the magnitude: a model that is wildly wrong in both
/// directions can have near-zero bias and be useless. A coefficient should only
/// ever be tuned against bias.
public struct CalibrationSummary: Sendable, Equatable {
    public let count: Int
    public let heightBiasMeters: Double
    public let heightRMSEMeters: Double
    public let periodBiasSeconds: Double
    public let periodRMSESeconds: Double
    /// Bias measured against the swell partition, over the records that carry
    /// one. `nil` until some do.
    ///
    /// Reported beside `heightBiasMeters` rather than replacing it, because the
    /// gap between the two IS the finding: if the combined bias stays large
    /// while this one sits near zero, the model is fine and the comparison was
    /// wrong. Only this number may be tuned against.
    public let swellHeightBiasMeters: Double?
    public let swellCount: Int

    public init(records: [CalibrationRecord]) {
        count = records.count
        guard !records.isEmpty else {
            heightBiasMeters = 0; heightRMSEMeters = 0
            periodBiasSeconds = 0; periodRMSESeconds = 0
            swellHeightBiasMeters = nil; swellCount = 0
            return
        }
        let n = Double(records.count)
        let he = records.map(\.heightErrorMeters)
        let pe = records.map(\.periodErrorSeconds)
        heightBiasMeters = he.reduce(0, +) / n
        periodBiasSeconds = pe.reduce(0, +) / n
        heightRMSEMeters = (he.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
        periodRMSESeconds = (pe.reduce(0) { $0 + $1 * $1 } / n).squareRoot()

        // Only over the records that carry a partition, so adding the field does
        // not silently reinterpret the history written before it existed.
        let se = records.compactMap(\.swellHeightErrorMeters)
        swellCount = se.count
        swellHeightBiasMeters = se.isEmpty ? nil : se.reduce(0, +) / Double(se.count)
    }

    /// The multiplier that would remove the height bias.
    ///
    /// Applied to a spot's `exposureCoefficient` this is the whole point of the
    /// exercise — but only once there are enough records for the bias to mean
    /// anything, which is why the count travels with it.
    ///
    /// **Measured against the swell partition, never the combined sea.** The
    /// combined bias is contaminated by a definition mismatch: an ISRAMAR buoy
    /// and a model's combined `wave_height` are not the same quantity, and on
    /// 2026-08-29 they differed by 0.46 m at Bat Yam while the swell channel
    /// agreed to 2 cm. Correcting a spot's sheltering to cancel that would be
    /// tuning the transform for an error made somewhere else entirely.
    ///
    /// Returns `nil` — refusing to guess — until 30 records carry a partition,
    /// even if hundreds of older records are present.
    public func suggestedHeightCorrection(againstMeanObserved mean: Double) -> Double? {
        guard swellCount >= 30, mean > 0.01, let bias = swellHeightBiasMeters else { return nil }
        return mean / (mean + bias)
    }
}

public enum CalibrationLog {
    /// JSON Lines: one record per line, appended, never rewritten. A crash mid
    /// write costs one line rather than the whole history.
    public static func append(_ record: CalibrationRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(contentsOf: [0x0A])

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            try line.write(to: url)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Tolerates a corrupt line rather than losing the file: a half-written
    /// record from an interrupted run must not make the history unreadable.
    public static func read(from url: URL) throws -> [CalibrationRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(CalibrationRecord.self, from: data)
        }
    }

    public static func summarise(_ records: [CalibrationRecord], spotID: String? = nil) -> CalibrationSummary {
        CalibrationSummary(records: spotID.map { id in records.filter { $0.spotID == id } } ?? records)
    }
}
