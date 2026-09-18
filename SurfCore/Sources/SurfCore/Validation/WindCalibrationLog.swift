import Foundation

/// One model-versus-measurement pair for wind, kept so the question "does this
/// station describe this beach?" can eventually be answered with a series rather
/// than an impression.
///
/// Its own file — `calibration/wind_observations.jsonl` — rather than new fields
/// on `CalibrationRecord`. The wave ledger pairs a model hour against a buoy and
/// is written only when both exist; wind pairs exist on completely different
/// hours, and widening the wave record would have meant either optional noise in
/// every line or, worse, a non-optional field that makes every existing line
/// undecodable.
///
/// Until this series is long enough to show a station tracks its beach, measured
/// wind stays a readout and a safety input and is deliberately kept out of the
/// sea state and the score.
public struct WindCalibrationRecord: Sendable, Codable, Equatable {
    public let recordedAt: Date
    public let spotID: String
    public let stationID: String
    public let observedAt: Date
    /// Straight-line distance from the beach to the mast, km — the first thing
    /// any disagreement has to be read against.
    public let stationDistanceKilometres: Double

    public let modelWindSpeedMPS: Double
    public let modelWindDirectionDegrees: Double
    public let modelWindGustMPS: Double?

    public let measuredWindSpeedMPS: Double
    public let measuredWindDirectionDegrees: Double
    public let measuredWindGustMPS: Double?

    public init(
        recordedAt: Date,
        spotID: String,
        stationID: String,
        observedAt: Date,
        stationDistanceKilometres: Double,
        modelWindSpeedMPS: Double,
        modelWindDirectionDegrees: Double,
        modelWindGustMPS: Double?,
        measuredWindSpeedMPS: Double,
        measuredWindDirectionDegrees: Double,
        measuredWindGustMPS: Double?
    ) {
        self.recordedAt = recordedAt
        self.spotID = spotID
        self.stationID = stationID
        self.observedAt = observedAt
        self.stationDistanceKilometres = stationDistanceKilometres
        self.modelWindSpeedMPS = modelWindSpeedMPS
        self.modelWindDirectionDegrees = modelWindDirectionDegrees
        self.modelWindGustMPS = modelWindGustMPS
        self.measuredWindSpeedMPS = measuredWindSpeedMPS
        self.measuredWindDirectionDegrees = measuredWindDirectionDegrees
        self.measuredWindGustMPS = measuredWindGustMPS
    }

    /// Signed, in knots: positive means the model blew harder than the station.
    public var speedBiasKnots: Double {
        Units.knots(fromMetersPerSecond: modelWindSpeedMPS - measuredWindSpeedMPS)
    }

    /// Smallest angle between the two bearings, 0...180. A plain subtraction
    /// calls 350° and 10° a 340-degree disagreement when it is twenty.
    public var directionErrorDegrees: Double {
        Compass.angularDistance(modelWindDirectionDegrees, measuredWindDirectionDegrees)
    }
}

public struct WindCalibrationSummary: Sendable, Equatable {
    public let count: Int
    /// Positive: the model reads windier than the coast does.
    public let speedBiasKnots: Double
    public let speedRMSEKnots: Double
    public let directionMeanAbsoluteErrorDegrees: Double
    /// How often model and station agree about the thing that actually matters:
    /// whether the wind is blowing off the land.
    public let offshoreAgreementRate: Double

    public init(records: [WindCalibrationRecord], shorelineNormalDegrees: Double) {
        count = records.count
        guard !records.isEmpty else {
            speedBiasKnots = 0
            speedRMSEKnots = 0
            directionMeanAbsoluteErrorDegrees = 0
            offshoreAgreementRate = 0
            return
        }

        let n = Double(records.count)
        speedBiasKnots = records.map(\.speedBiasKnots).reduce(0, +) / n
        speedRMSEKnots = (records.map { $0.speedBiasKnots * $0.speedBiasKnots }.reduce(0, +) / n)
            .squareRoot()
        directionMeanAbsoluteErrorDegrees = records.map(\.directionErrorDegrees).reduce(0, +) / n

        let agreements = records.filter { record in
            let model = Compass.windRelation(
                windFromDegrees: record.modelWindDirectionDegrees,
                shorelineNormalDegrees: shorelineNormalDegrees
            )
            let measured = Compass.windRelation(
                windFromDegrees: record.measuredWindDirectionDegrees,
                shorelineNormalDegrees: shorelineNormalDegrees
            )
            return model.blowsAwayFromShore == measured.blowsAwayFromShore
        }
        offshoreAgreementRate = Double(agreements.count) / n
    }
}

public enum WindCalibrationLog {
    public static func append(_ record: WindCalibrationRecord, to url: URL) throws {
        try CalibrationLog.append(record, to: url)
    }

    public static func read(from url: URL) throws -> [WindCalibrationRecord] {
        try CalibrationLog.read(WindCalibrationRecord.self, from: url)
    }

    public static func summarise(
        _ records: [WindCalibrationRecord],
        spotID: String? = nil,
        shorelineNormalDegrees: Double
    ) -> WindCalibrationSummary {
        WindCalibrationSummary(
            records: spotID.map { id in records.filter { $0.spotID == id } } ?? records,
            shorelineNormalDegrees: shorelineNormalDegrees
        )
    }
}
