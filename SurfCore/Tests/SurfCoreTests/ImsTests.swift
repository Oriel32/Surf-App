import Foundation
import Testing
@testable import SurfCore

/// Every fixture here is a verbatim capture from the live IMS API on
/// 2026-09-18, except `ims_tel_aviv_coast_daily_20260829`, which is the real
/// payload trimmed to the 09:00–11:00 window; its values are untouched.
@Suite("IMS measured wind")
struct ImsTests {
    // MARK: - The timestamp trap

    /// The regression test for the bug this decoder was built around.
    ///
    /// `2026-09-18T10:50:00+03:00` was served when the real local time was 09:10
    /// IDT. Believing the `+03:00` puts the reading at 07:50 UTC — 1 h 20 min in
    /// the past, permanently stale. It is really 08:50 UTC: local *standard*
    /// time, which IMS quotes all year round, twenty minutes before the capture.
    @Test("The +03:00 suffix is a lie: timestamps are local standard time")
    func timestampIsLocalStandardTime() throws {
        let readings = try ImsClient.parse(
            try Fixture.data("ims_tel_aviv_coast_latest"),
            stationID: "tel-aviv-coast"
        )

        #expect(readings.count == 1)
        #expect(readings[0].observedAt == Date.utc(2026, 9, 18, 8, 50))
        #expect(readings[0].observedAt != Date.utc(2026, 9, 18, 7, 50))
    }

    @Test("Twenty minutes old is fresh; the naive reading of the same payload would not be")
    func freshnessSurvivesTheOffset() throws {
        let reading = try ImsClient.parse(
            try Fixture.data("ims_tel_aviv_coast_latest"),
            stationID: "tel-aviv-coast"
        )[0]
        let capturedAt = Date.utc(2026, 9, 18, 9, 10)

        #expect(reading.isFresh(asOf: capturedAt))
        #expect(abs(reading.age(asOf: capturedAt) - 20 * 60) < 1)
        // An hour-and-a-half later it is not "now" any more. Wind is perishable.
        #expect(!reading.isFresh(asOf: capturedAt.addingTimeInterval(3600)))
    }

    // MARK: - Values

    @Test("The live payload decodes to SI, by channel name")
    func decodesLiveReading() throws {
        let reading = try ImsClient.parse(
            try Fixture.data("ims_tel_aviv_coast_latest"),
            stationID: "tel-aviv-coast"
        )[0]

        #expect(reading.windSpeedMPS == 8.2)
        #expect(reading.windDirectionDegrees == 266.0)
        #expect(reading.windGustMPS == 10.5)
        #expect(reading.airTemperatureC == 29.9)
        // 8.2 m/s is just under 16 knots — a solid onshore westerly, not a
        // number that has been quietly converted somewhere.
        #expect(abs(Units.knots(fromMetersPerSecond: reading.windSpeedMPS) - 15.9) < 0.1)
    }

    /// Channel ids are not stable between stations — the IMS documentation
    /// highlights exactly this — so the lookup must be by name. Here the ids are
    /// shuffled and the values must still land in the right fields.
    @Test("Channels are found by name, not by id")
    func findsChannelsByName() throws {
        let payload = Data("""
        {"stationId": 999, "data": [{"datetime": "2026-09-18T10:50:00+03:00", "channels": [
          {"id": 41, "name": "WD", "value": 90.0, "status": 1, "valid": true},
          {"id": 7, "name": "WS", "value": 5.0, "status": 1, "valid": true},
          {"id": 2, "name": "WSmax", "value": 9.0, "status": 1, "valid": true}
        ]}]}
        """.utf8)

        let reading = try ImsClient.parse(payload, stationID: "tel-aviv-coast")[0]
        #expect(reading.windSpeedMPS == 5.0)
        #expect(reading.windDirectionDegrees == 90.0)
        #expect(reading.windGustMPS == 9.0)
        #expect(reading.airTemperatureC == nil)
    }

    // MARK: - The validity trap

    /// Elat's anemometer is dead. It reports `0.0` with `status: 2, valid: false`
    /// on every slice, and a decoder that reads `value` without the flags would
    /// publish dead calm in the one basin where wind *is* the wave model.
    @Test("A flagged-invalid zero is refused, not published as calm")
    func invalidSensorIsRefused() throws {
        #expect(throws: SourceError.self) {
            _ = try ImsClient.parse(
                try Fixture.data("ims_elat_invalid_wind"),
                stationID: "elat"
            )
        }
    }

    @Test("status 2 alone is enough to reject a value")
    func statusFlagAloneRejects() throws {
        let payload = Data("""
        {"stationId": 999, "data": [{"datetime": "2026-09-18T10:50:00+03:00", "channels": [
          {"id": 4, "name": "WS", "value": 0.0, "status": 2, "valid": true},
          {"id": 5, "name": "WD", "value": 0.0, "status": 1, "valid": true}
        ]}]}
        """.utf8)

        #expect(throws: SourceError.self) {
            _ = try ImsClient.parse(payload, stationID: "tel-aviv-coast")
        }
    }

    // MARK: - History, for checking a field report after the fact

    @Test("The nearest slice is chosen, and the gust is the hour's peak")
    func nearestSliceCarriesHourlyGust() throws {
        let readings = try ImsClient.parse(
            try Fixture.data("ims_tel_aviv_coast_daily_20260829"),
            stationID: "tel-aviv-coast"
        )
        // 10:00 local standard time on 2026-08-29 is 08:00 UTC.
        let reading = try ImsClient.nearest(to: Date.utc(2026, 8, 29, 8, 0), in: readings)

        #expect(reading.observedAt == Date.utc(2026, 8, 29, 8, 0))
        #expect(reading.windSpeedMPS == 3.8)
        #expect(reading.windDirectionDegrees == 226.0)
        // The mean at that slice gusted to 6.7, but the model's hourly gust means
        // the peak of the hour, so the comparison has to be like for like.
        let sliceGusts = readings
            .filter { $0.observedAt > Date.utc(2026, 8, 29, 7, 0) && $0.observedAt <= Date.utc(2026, 8, 29, 8, 0) }
            .compactMap(\.windGustMPS)
        #expect(reading.windGustMPS == sliceGusts.max())
        #expect((reading.windGustMPS ?? 0) >= 6.7)
    }

    @Test("The daily path is built in standard time, not the machine's zone")
    func dayPathUsesStandardTime() {
        // 2026-08-29T22:30 UTC is 00:30 on the 30th in standard time.
        #expect(DateParsing.imsDayPath(for: Date.utc(2026, 8, 29, 22, 30)) == "2026/08/30")
        #expect(DateParsing.imsDayPath(for: Date.utc(2026, 8, 29, 8, 0)) == "2026/08/29")
    }

    // MARK: - Transport

    @Test("An unknown station never reaches the network")
    func unknownStationThrowsEarly() async {
        let client = ImsClient(
            token: "unused",
            transport: StubTransport(payload: Data("{}".utf8))
        )
        await #expect(throws: SourceError.unknownStation("nowhere")) {
            _ = try await client.latestWind(stationID: "nowhere")
        }
    }

    /// The token goes in a header and nowhere else. A token in a URL leaks into
    /// caches, logs and the calibration ledger.
    @Test("The token is sent as an ApiToken header and never in the URL")
    func tokenTravelsInTheHeader() async throws {
        let recorder = URLRecorder()
        let client = ImsClient(
            token: "secret-token",
            transport: RecordingTransport(
                payload: try Fixture.data("ims_tel_aviv_coast_latest"),
                recorder: recorder
            )
        )

        _ = try await client.latestWind(stationID: "tel-aviv-coast")

        let requested = await recorder.urls
        let sentHeaders = await recorder.headers
        #expect(requested.count == 1)
        #expect(requested[0].absoluteString.contains("/stations/178/data/latest"))
        #expect(!requested[0].absoluteString.contains("secret-token"))
        #expect(sentHeaders[0]["Authorization"] == "ApiToken secret-token")
    }

    @Test("Every spot's wind station exists in the table")
    func catalogueStationsResolve() throws {
        for spot in try SpotCatalog.load() {
            guard let stationID = spot.windStationID else { continue }
            #expect(ImsClient.stations[stationID] != nil, "unknown wind station \(stationID)")
        }
    }
}
