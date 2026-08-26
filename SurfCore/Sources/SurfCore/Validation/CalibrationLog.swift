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

    public let buoyHeightMeters: Double
    public let buoyPeakPeriodSeconds: Double

    public init(
        recordedAt: Date,
        spotID: String,
        stationID: String,
        observedAt: Date,
        modelOpenSeaHeightMeters: Double,
        modelPeriodSeconds: Double,
        buoyHeightMeters: Double,
        buoyPeakPeriodSeconds: Double
    ) {
        self.recordedAt = recordedAt
        self.spotID = spotID
        self.stationID = stationID
        self.observedAt = observedAt
        self.modelOpenSeaHeightMeters = modelOpenSeaHeightMeters
        self.modelPeriodSeconds = modelPeriodSeconds
        self.buoyHeightMeters = buoyHeightMeters
        self.buoyPeakPeriodSeconds = buoyPeakPeriodSeconds
    }

    /// Signed. Positive means the model runs bigger than the sea.
    public var heightErrorMeters: Double {
        modelOpenSeaHeightMeters - buoyHeightMeters
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

    public init(records: [CalibrationRecord]) {
        count = records.count
        guard !records.isEmpty else {
            heightBiasMeters = 0; heightRMSEMeters = 0
            periodBiasSeconds = 0; periodRMSESeconds = 0
            return
        }
        let n = Double(records.count)
        let he = records.map(\.heightErrorMeters)
        let pe = records.map(\.periodErrorSeconds)
        heightBiasMeters = he.reduce(0, +) / n
        periodBiasSeconds = pe.reduce(0, +) / n
        heightRMSEMeters = (he.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
        periodRMSESeconds = (pe.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
    }

    /// The multiplier that would remove the height bias.
    ///
    /// Applied to a spot's `exposureCoefficient` this is the whole point of the
    /// exercise — but only once there are enough records for the bias to mean
    /// anything, which is why `count` travels with it.
    public func suggestedHeightCorrection(againstMeanObserved mean: Double) -> Double? {
        guard count >= 30, mean > 0.01 else { return nil }
        return mean / (mean + heightBiasMeters)
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
