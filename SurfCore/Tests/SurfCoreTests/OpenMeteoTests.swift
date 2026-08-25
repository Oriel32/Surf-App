import Foundation
import Testing
@testable import SurfCore

/// Records which endpoints a client actually calls.
actor URLRecorder {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

struct RecordingTransport: HTTPTransport {
    let payload: Data
    let recorder: URLRecorder

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        await recorder.record(url)
        return payload
    }
}

@Suite("Open-Meteo client")
struct OpenMeteoClientTests {
    /// Atmospheric-only response: no wave fields at all, which is exactly what
    /// the Eilat path has to work from.
    private let weatherPayload = Data("""
    {"hourly":{
      "time":["2026-08-25T00:00","2026-08-25T01:00","2026-08-25T02:00"],
      "wind_speed_10m":[3.0,5.0,7.0],
      "wind_direction_10m":[90.0,95.0,100.0],
      "temperature_2m":[28.0,27.5,27.0]}}
    """.utf8)

    private let marinePayload = Data("""
    {"hourly":{
      "time":["2026-08-25T00:00","2026-08-25T01:00","2026-08-25T02:00"],
      "wave_height":[1.0,1.1,1.2],
      "wave_period":[8.0,8.5,9.0],
      "wave_direction":[270.0,272.0,274.0]}}
    """.utf8)

    @Test("A Gulf of Eilat spot never calls the marine endpoint")
    func eilatSkipsMarineEndpoint() async throws {
        // Found by the live smoke test, not by any fixture: Open-Meteo Marine
        // answers HTTP 400 for Eilat's coordinates because the gulf is outside
        // its model domain. Calling it anyway failed the entire fetch and left
        // Eilat with no forecast at all.
        let recorder = URLRecorder()
        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: weatherPayload, recorder: recorder)
        )
        let eilat = Spot.fixture(shorelineNormalDegrees: 200, basin: .gulfOfEilat)

        let samples = try await client.forecast(for: eilat)
        let urls = await recorder.urls

        #expect(urls.count == 1, "Eilat must issue exactly one request")
        #expect(urls.allSatisfy { $0.host?.contains("marine") == false })
        #expect(samples.count == 3)
        #expect(samples.first?.windSpeedMPS == 3.0)
    }

    @Test("Eilat samples carry wind and let the transform synthesise the waves")
    func eilatSamplesFeedTheSyntheticPath() async throws {
        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: weatherPayload, recorder: URLRecorder())
        )
        let eilat = Spot.fixture(shorelineNormalDegrees: 200, basin: .gulfOfEilat)

        let samples = try await client.forecast(for: eilat)
        let last = try #require(samples.last)

        // The client reports no wave data, because there is none to report.
        #expect(last.waveHeightMeters == 0)

        // The transform fills it in from the wind, and flags it as derived.
        let conditions = WaveTransform.transform(last, at: eilat)
        #expect(conditions.isSynthetic)
        #expect(conditions.waveHeightMeters > 0)
    }

    @Test("A Mediterranean spot calls both endpoints")
    func mediterraneanCallsBoth() async throws {
        let recorder = URLRecorder()
        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: marinePayload, recorder: recorder)
        )

        _ = try? await client.forecast(for: .fixture())
        let urls = await recorder.urls

        #expect(urls.count == 2)
        #expect(urls.contains { $0.host?.contains("marine") == true })
        #expect(urls.contains { $0.host?.contains("marine") == false })
    }

    @Test("The requested model is passed through to the marine endpoint")
    func modelIsRequested() async throws {
        let recorder = URLRecorder()
        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: marinePayload, recorder: recorder),
            model: "best_match"
        )

        _ = try? await client.forecast(for: .fixture())
        let urls = await recorder.urls
        let marine = try #require(urls.first { $0.host?.contains("marine") == true })

        // ewam is the highest-resolution model but expires after ~3.8 days,
        // leaving 77 of 168 hours null. best_match keeps the full week.
        #expect(marine.query?.contains("models=best_match") == true)
    }

    @Test("Wind speed is requested in SI so nothing downstream converts")
    func windIsRequestedInMetresPerSecond() async throws {
        let recorder = URLRecorder()
        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: weatherPayload, recorder: recorder)
        )

        _ = try? await client.forecast(for: .fixture(basin: .gulfOfEilat))
        let urls = await recorder.urls
        let weather = try #require(urls.first)

        #expect(weather.query?.contains("wind_speed_unit=ms") == true)
    }

    @Test("Rows with missing values are dropped, not defaulted to zero")
    func nullRowsAreDropped() async throws {
        let holes = Data("""
        {"hourly":{
          "time":["2026-08-25T00:00","2026-08-25T01:00"],
          "wind_speed_10m":[3.0,null],
          "wind_direction_10m":[90.0,95.0],
          "temperature_2m":[28.0,27.5]}}
        """.utf8)

        let client = OpenMeteoClient(
            transport: RecordingTransport(payload: holes, recorder: URLRecorder())
        )
        let samples = try await client.forecast(for: .fixture(basin: .gulfOfEilat))

        // A null wind reading must not silently become a calm, glassy hour.
        #expect(samples.count == 1)
    }
}
