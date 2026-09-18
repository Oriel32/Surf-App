import Foundation
import Testing
@testable import SurfCore

@Suite("Calibration log")
struct CalibrationTests {
    private func record(
        spot: String = "hadera",
        model: Double,
        buoy: Double,
        modelPeriod: Double = 6.3,
        buoyPeriod: Double = 6.5,
        modelSwell: Double? = nil
    ) -> CalibrationRecord {
        CalibrationRecord(
            recordedAt: .utc(2026, 8, 26, 17),
            spotID: spot,
            stationID: "hadera",
            observedAt: .utc(2026, 8, 26, 17),
            modelOpenSeaHeightMeters: model,
            modelPeriodSeconds: modelPeriod,
            modelSwellHeightMeters: modelSwell,
            buoyHeightMeters: buoy,
            buoyPeakPeriodSeconds: buoyPeriod
        )
    }

    @Test("Error is signed, so a model that runs big is distinguishable from one that runs small")
    func errorIsSigned() {
        #expect(abs(record(model: 0.8, buoy: 0.6).heightErrorMeters - 0.2) < 1e-9)
        #expect(abs(record(model: 0.4, buoy: 0.6).heightErrorMeters + 0.2) < 1e-9)
    }

    @Test("Bias and RMSE say different things about the same errors")
    func biasIsNotRMSE() {
        // Consistently 0.2 m high: large bias, easy to correct.
        let biased = [record(model: 0.8, buoy: 0.6), record(model: 1.2, buoy: 1.0)]
        let biasedSummary = CalibrationSummary(records: biased)
        #expect(abs(biasedSummary.heightBiasMeters - 0.2) < 1e-9)
        #expect(abs(biasedSummary.heightRMSEMeters - 0.2) < 1e-9)

        // Wildly wrong in both directions: near-zero bias, useless model. A
        // summary that reported only bias would call this one perfect.
        let scattered = [record(model: 1.1, buoy: 0.6), record(model: 0.1, buoy: 0.6)]
        let scatteredSummary = CalibrationSummary(records: scattered)
        #expect(abs(scatteredSummary.heightBiasMeters) < 1e-9)
        #expect(scatteredSummary.heightRMSEMeters > 0.4)
    }

    @Test("An empty history summarises to zero rather than dividing by it")
    func emptyIsSafe() {
        let summary = CalibrationSummary(records: [])
        #expect(summary.count == 0)
        #expect(summary.heightRMSEMeters == 0)
    }

    @Test("A correction is withheld until there is enough data to justify one")
    func refusesToTuneOnThinData() {
        // Two observations cannot tune a coefficient, and pretending otherwise
        // is how a plausible-looking number gets baked in.
        let thin = CalibrationSummary(records: [record(model: 0.8, buoy: 0.6, modelSwell: 0.8)])
        #expect(thin.suggestedHeightCorrection(againstMeanObserved: 0.6) == nil)

        let plenty = CalibrationSummary(
            records: (0..<40).map { _ in record(model: 0.8, buoy: 0.6, modelSwell: 0.8) }
        )
        let correction = plenty.suggestedHeightCorrection(againstMeanObserved: 0.6)
        #expect(correction != nil)
        // Model reads 0.8 where the sea is 0.6, so it needs scaling down.
        #expect((correction ?? 1) < 1.0)
    }

    @Test("A history with no swell partition cannot tune anything, however long it is")
    func refusesToTuneOnTheCombinedSea() {
        // 2026-08-29 at Bat Yam: the combined sea read 1.10 m against a 0.64 m
        // buoy — a +0.46 m error that looks like a badly calibrated transform.
        // The swell partition that hour was 0.66 m: right to 2 cm. The gap was a
        // definition mismatch between a model's combined `wave_height` and what
        // the buoy reports, and correcting a spot's sheltering to cancel it
        // would break every spot to fix nothing.
        let combinedOnly = CalibrationSummary(
            records: (0..<40).map { _ in record(model: 1.10, buoy: 0.64) }
        )
        #expect(combinedOnly.count == 40)
        #expect(abs(combinedOnly.heightBiasMeters - 0.46) < 1e-9)
        // No partition captured, so no correction — however much data there is.
        #expect(combinedOnly.swellHeightBiasMeters == nil)
        #expect(combinedOnly.suggestedHeightCorrection(againstMeanObserved: 0.64) == nil)

        // The same hours with the partition recorded: the swell channel is
        // nearly unbiased, and that is the number allowed to move a coefficient.
        let partitioned = CalibrationSummary(
            records: (0..<40).map { _ in record(model: 1.10, buoy: 0.64, modelSwell: 0.66) }
        )
        #expect(abs(partitioned.heightBiasMeters - 0.46) < 1e-9)
        #expect(abs((partitioned.swellHeightBiasMeters ?? 9) - 0.02) < 1e-9)
        #expect(partitioned.swellCount == 40)

        // A 2 cm bias on a 0.64 m sea barely moves anything — which is the
        // point. Tuning against the combined 0.46 m would have shrunk every
        // coefficient by more than a third.
        let correction = partitioned.suggestedHeightCorrection(againstMeanObserved: 0.64)
        #expect((correction ?? 0) > 0.95)
    }

    @Test("Records survive a round trip through the log file")
    func roundTrips() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cal-\(UUID().uuidString)")
            .appendingPathComponent("observations.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CalibrationLog.append(record(model: 0.8, buoy: 0.6), to: url)
        try CalibrationLog.append(record(model: 0.9, buoy: 0.7), to: url)

        let read = try CalibrationLog.read(from: url)
        #expect(read.count == 2)
        #expect(abs(read[1].modelOpenSeaHeightMeters - 0.9) < 1e-9)
    }

    @Test("A corrupt line costs one record, not the whole history")
    func toleratesCorruption() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cal-\(UUID().uuidString)")
            .appendingPathComponent("observations.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CalibrationLog.append(record(model: 0.8, buoy: 0.6), to: url)
        // An interrupted run leaves a half-written line behind.
        if let handle = FileHandle(forWritingAtPath: url.path) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("{\"spotID\":\"hade".utf8))
            try handle.close()
        }
        #expect(try CalibrationLog.read(from: url).count == 1)
    }

    @Test("Summaries can be scoped to one spot")
    func filtersBySpot() {
        let mixed = [
            record(spot: "hadera", model: 0.8, buoy: 0.6),
            record(spot: "palmachim", model: 2.0, buoy: 0.6)
        ]
        #expect(CalibrationLog.summarise(mixed).count == 2)
        #expect(CalibrationLog.summarise(mixed, spotID: "hadera").count == 1)
    }

    @Test("Reading a log that does not exist yet is empty, not an error")
    func missingFileIsEmpty() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nope-\(UUID().uuidString).jsonl")
        #expect(try CalibrationLog.read(from: url).isEmpty)
    }
}

@Suite("Wind calibration log")
struct WindCalibrationTests {
    private func record(
        spot: String = "bat-yam",
        modelMPS: Double,
        modelDirection: Double,
        measuredMPS: Double,
        measuredDirection: Double
    ) -> WindCalibrationRecord {
        WindCalibrationRecord(
            recordedAt: .utc(2026, 9, 18, 9, 0),
            spotID: spot,
            stationID: "178",
            observedAt: .utc(2026, 9, 18, 8, 50),
            stationDistanceKilometres: 4.9,
            modelWindSpeedMPS: modelMPS,
            modelWindDirectionDegrees: modelDirection,
            modelWindGustMPS: nil,
            measuredWindSpeedMPS: measuredMPS,
            measuredWindDirectionDegrees: measuredDirection,
            measuredWindGustMPS: nil
        )
    }

    @Test("Bias is signed: positive means the model blew harder than the coast")
    func biasIsSigned() {
        let modelWindier = record(modelMPS: 8, modelDirection: 270, measuredMPS: 5, measuredDirection: 270)
        #expect(modelWindier.speedBiasKnots > 0)
        #expect(abs(modelWindier.speedBiasKnots - Units.knots(fromMetersPerSecond: 3)) < 1e-9)
    }

    /// The live run on 2026-09-18 compared 246° against 158°: a plain subtraction
    /// is fine there, but 350 against 10 is a twenty-degree disagreement and
    /// subtraction calls it 340.
    @Test("Direction error wraps around north")
    func directionErrorWrapsAroundNorth() {
        let wrapping = record(modelMPS: 5, modelDirection: 350, measuredMPS: 5, measuredDirection: 10)
        #expect(abs(wrapping.directionErrorDegrees - 20) < 1e-9)
    }

    /// The only direction question the safety layer asks.
    @Test("Agreement is measured on whether the wind blows off the land")
    func offshoreAgreementIsWhatCounts() {
        // A west-facing beach: 270 is onshore, 90 is offshore.
        let bothOnshore = record(modelMPS: 5, modelDirection: 250, measuredMPS: 6, measuredDirection: 280)
        let disagreeing = record(modelMPS: 5, modelDirection: 270, measuredMPS: 6, measuredDirection: 90)

        let agreeing = WindCalibrationLog.summarise([bothOnshore], shorelineNormalDegrees: 270)
        #expect(agreeing.offshoreAgreementRate == 1.0)

        let mixed = WindCalibrationLog.summarise([bothOnshore, disagreeing], shorelineNormalDegrees: 270)
        #expect(mixed.offshoreAgreementRate == 0.5)
    }

    @Test("An empty history summarises to zero rather than a division by zero")
    func emptyIsSafe() {
        let summary = WindCalibrationLog.summarise([], shorelineNormalDegrees: 270)
        #expect(summary.count == 0)
        #expect(summary.speedRMSEKnots == 0)
    }

    @Test("Wind records survive a round trip, in their own file")
    func roundTrips() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wind-\(UUID().uuidString)")
            .appendingPathComponent("wind_observations.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try WindCalibrationLog.append(record(modelMPS: 5, modelDirection: 270, measuredMPS: 8, measuredDirection: 266), to: url)
        try WindCalibrationLog.append(record(modelMPS: 6, modelDirection: 250, measuredMPS: 7, measuredDirection: 260), to: url)

        let read = try WindCalibrationLog.read(from: url)
        #expect(read.count == 2)
        #expect(abs(read[1].measuredWindSpeedMPS - 7) < 1e-9)
        #expect(read[0].stationDistanceKilometres == 4.9)
    }

    /// The reason wind got its own ledger. The wave log is read with a tolerant
    /// decoder, so a record type that gained a required field would drop every
    /// line already on disk — silently, and only the history can ever tune a
    /// coefficient.
    @Test("The wave ledger still decodes its existing lines")
    func waveLedgerIsUntouched() throws {
        let committed = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SurfCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // SurfCore
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("calibration")
            .appendingPathComponent("observations.jsonl")

        let lines = (try? String(contentsOf: committed, encoding: .utf8))?
            .split(whereSeparator: \.isNewline).count ?? 0
        let decoded = try CalibrationLog.read(from: committed).count
        #expect(lines > 0, "the committed ledger is empty — did it get truncated?")
        #expect(decoded == lines, "path \(committed.path): \(lines) lines, \(decoded) decoded")
    }

    /// The bug this caught on 2026-09-18, and the reason `.gitattributes` now
    /// pins these files to LF.
    ///
    /// Swift treats "\r\n" as a single grapheme that does not equal "\n", so a
    /// `split(separator: "\n")` over a CRLF ledger returns the entire file as one
    /// line, which then fails to decode and is dropped by the tolerant reader —
    /// silently, because tolerance is the whole point of that reader. Git checks
    /// these files out with CRLF on this machine, so eleven Bat Yam observations
    /// were invisible while the smoke test cheerfully reported "0 observation(s)
    /// for this spot".
    @Test("A ledger with Windows line endings is read, not silently emptied")
    func readsCRLFLedger() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crlf-\(UUID().uuidString)")
            .appendingPathComponent("observations.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // Written the way a Windows checkout leaves it.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let one = try encoder.encode(record(modelMPS: 5, modelDirection: 270, measuredMPS: 8, measuredDirection: 266))
        let two = try encoder.encode(record(modelMPS: 6, modelDirection: 250, measuredMPS: 7, measuredDirection: 260))
        var crlf = Data()
        for line in [one, two] {
            crlf.append(line)
            crlf.append(contentsOf: [0x0D, 0x0A])
        }
        try crlf.write(to: url)

        #expect(try WindCalibrationLog.read(from: url).count == 2)
    }
}
