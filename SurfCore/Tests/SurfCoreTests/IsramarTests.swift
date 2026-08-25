import Foundation
import Testing
@testable import SurfCore

@Suite("ISRAMAR buoy parsing and staleness")
struct IsramarTests {
    /// A moment shortly after the live Hadera reading was captured.
    private let now = Date.utc(2026, 8, 25, 17, 0)

    @Test("The live Hadera payload parses")
    func parsesLiveReading() throws {
        let observation = try IsramarClient.parse(
            try Fixture.data("isramar_hadera_live"),
            stationID: "hadera"
        )

        #expect(observation.significantWaveHeightMeters == 0.66)
        #expect(observation.peakPeriodSeconds == 6.2)
        #expect(observation.observedAt == Date.utc(2026, 8, 25, 16, 0))
        #expect(observation.maximumWaveHeightMeters != nil)
    }

    @Test("An hour-old reading is fresh")
    func recentReadingIsFresh() throws {
        let observation = try IsramarClient.parse(
            try Fixture.data("isramar_hadera_live"),
            stationID: "hadera"
        )
        #expect(observation.isFresh(asOf: now))
        #expect(abs(observation.age(asOf: now) - 3600) < 1)
    }

    @Test("The dead Shikmona buoy's reading is rejected as stale")
    func staleReadingIsRejected() throws {
        // This is the headline bug this gate exists to prevent. The endpoint
        // returns HTTP 200 with a perfectly well-formed payload — it is simply
        // seven months old, because the buoy is offline and the file is still
        // being served. Rendering this 4.09 m storm as the current sea during a
        // flat August afternoon would be the worst thing this app could do.
        let observation = try IsramarClient.parse(
            try Fixture.data("isramar_shikmona_stale"),
            stationID: "shikmona"
        )

        #expect(observation.significantWaveHeightMeters == 4.09)
        #expect(observation.isFresh(asOf: now) == false)
        #expect(observation.age(asOf: now) > 30 * 24 * 3600)
    }

    @Test("A reading from the future is not treated as fresh")
    func futureReadingIsNotFresh() {
        // A clock skew or a timezone bug at the source must not read as "just
        // measured".
        let observation = BuoyObservation(
            stationID: "hadera",
            observedAt: now.addingTimeInterval(6 * 3600),
            significantWaveHeightMeters: 1.0,
            peakPeriodSeconds: 7
        )
        #expect(observation.isFresh(asOf: now) == false)
    }

    @Test("An unknown station is rejected before any request is made")
    func unknownStationThrows() async {
        let client = IsramarClient(transport: StubTransport(payload: Data()))
        await #expect(throws: SourceError.unknownStation("nahariya")) {
            try await client.latestObservation(stationID: "nahariya")
        }
    }

    @Test("Garbage in the payload throws rather than yielding a plausible number")
    func malformedPayloadThrows() {
        let garbage = Data(#"{"datetime": "not a date", "parameters": []}"#.utf8)
        #expect(throws: (any Error).self) {
            try IsramarClient.parse(garbage, stationID: "hadera")
        }
    }

    @Test("A payload missing wave height throws instead of defaulting to zero")
    func missingParametersThrow() {
        let partial = Data("""
        {"datetime": "2026-08-25 16:00 UTC",
         "parameters": [{"name": "Peak wave period", "units": "s", "values": [6.2]}]}
        """.utf8)
        #expect(throws: (any Error).self) {
            try IsramarClient.parse(partial, stationID: "hadera")
        }
    }

    @Test("Both verified stations are mapped to their real filenames")
    func stationFilenamesAreVerified() {
        // The casing genuinely differs between stations on the live server.
        #expect(IsramarClient.stationFiles["hadera"] == "Hadera_Hs_Per")
        #expect(IsramarClient.stationFiles["shikmona"] == "ShikBuoy_HS_Per")
    }

    @Test("The client returns the reading and leaves the freshness call to the caller")
    func clientReturnsObservationForCallerToJudge() async throws {
        let client = IsramarClient(
            transport: StubTransport(payload: try Fixture.data("isramar_shikmona_stale"))
        )
        let observation = try await client.latestObservation(stationID: "shikmona")

        // Parsing succeeds — staleness is a display decision, not a parse error,
        // so "the buoy is offline" stays reportable to the user.
        #expect(observation.significantWaveHeightMeters == 4.09)
        #expect(observation.isFresh(asOf: now) == false)
    }
}
