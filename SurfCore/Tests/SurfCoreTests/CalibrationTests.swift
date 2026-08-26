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
        buoyPeriod: Double = 6.5
    ) -> CalibrationRecord {
        CalibrationRecord(
            recordedAt: .utc(2026, 8, 26, 17),
            spotID: spot,
            stationID: "hadera",
            observedAt: .utc(2026, 8, 26, 17),
            modelOpenSeaHeightMeters: model,
            modelPeriodSeconds: modelPeriod,
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
        let thin = CalibrationSummary(records: [record(model: 0.8, buoy: 0.6)])
        #expect(thin.suggestedHeightCorrection(againstMeanObserved: 0.6) == nil)

        let plenty = CalibrationSummary(records: (0..<40).map { _ in record(model: 0.8, buoy: 0.6) })
        let correction = plenty.suggestedHeightCorrection(againstMeanObserved: 0.6)
        #expect(correction != nil)
        // Model reads 0.8 where the sea is 0.6, so it needs scaling down.
        #expect((correction ?? 1) < 1.0)
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
