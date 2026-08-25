import Foundation
import Testing
@testable import SurfCore

// MARK: - Stubs

struct StubForecastSource: ForecastSource {
    let identifier = "stub"
    var samples: [RawMarineSample] = []
    /// Concrete rather than `any Error`: existential `Error` is not Sendable,
    /// and `ForecastSource` requires Sendable conformance.
    var error: SourceError? = nil

    func forecast(for spot: Spot) async throws -> [RawMarineSample] {
        if let error { throw error }
        return samples
    }
}

actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Records how many times the network was actually hit, and dawdles long enough
/// for concurrent callers to collide.
struct CountingForecastSource: ForecastSource {
    let identifier = "counting"
    let counter: CallCounter
    let samples: [RawMarineSample]

    func forecast(for spot: Spot) async throws -> [RawMarineSample] {
        await counter.increment()
        try await Task.sleep(for: .milliseconds(40))
        return samples
    }
}

struct StubObservationSource: ObservationSource {
    let observation: BuoyObservation?

    func latestObservation(stationID: String) async throws -> BuoyObservation {
        guard let observation else { throw SourceError.unknownStation(stationID) }
        return observation
    }
}

struct StubEnsembleSource: ModelEnsembleSource {
    var spreads: [ModelSpread] = []
    var error: SourceError? = nil

    func ensemble(for spot: Spot) async throws -> [ModelSpread] {
        if let error { throw error }
        return spreads
    }
}

private func series(hours count: Int = 12) -> [RawMarineSample] {
    (0..<count).map { index in
        .fixture(timestamp: .utc(2026, 8, 25, index), waveHeightMeters: 1.0)
    }
}

// MARK: - Tests

@Suite("Forecast repository")
struct ForecastRepositoryTests {
    private let spot = Spot.fixture(buoyStationID: "hadera")
    private let profile = UserProfile(sport: .surfing, skill: .intermediate)
    private let now = Date.utc(2026, 8, 25, 17, 0)

    @Test("Concurrent requests for the same spot share one network call")
    func concurrentRequestsAreDeduplicated() async throws {
        // This matters commercially, not just for tidiness: Stormglass's free
        // tier allows roughly ten requests a day, and a cold launch can easily
        // ask five screens for the same spot at once.
        let counter = CallCounter()
        let repository = ForecastRepository(
            primary: CountingForecastSource(counter: counter, samples: series()),
            clock: { [now] in now }
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await repository.forecast(for: spot, profile: profile) }
            }
            try await group.waitForAll()
        }

        #expect(await counter.count == 1)
    }

    @Test("A second request inside the TTL is served from cache")
    func cacheServesRepeatRequests() async throws {
        let counter = CallCounter()
        let repository = ForecastRepository(
            primary: CountingForecastSource(counter: counter, samples: series()),
            clock: { [now] in now }
        )

        _ = try await repository.forecast(for: spot, profile: profile)
        _ = try await repository.forecast(for: spot, profile: profile)

        #expect(await counter.count == 1)
    }

    @Test("Invalidating the cache forces a refetch")
    func invalidateForcesRefetch() async throws {
        let counter = CallCounter()
        let repository = ForecastRepository(
            primary: CountingForecastSource(counter: counter, samples: series()),
            clock: { [now] in now }
        )

        _ = try await repository.forecast(for: spot, profile: profile)
        await repository.invalidate()
        _ = try await repository.forecast(for: spot, profile: profile)

        #expect(await counter.count == 2)
    }

    @Test("A fresh buoy reading is reported as fresh")
    func freshBuoyIsReported() async throws {
        let reading = BuoyObservation(
            stationID: "hadera",
            observedAt: now.addingTimeInterval(-3600),
            significantWaveHeightMeters: 0.66,
            peakPeriodSeconds: 6.2
        )
        let repository = ForecastRepository(
            primary: StubForecastSource(samples: series()),
            observations: StubObservationSource(observation: reading),
            clock: { [now] in now }
        )

        let forecast = try await repository.forecast(for: spot, profile: profile)
        #expect(forecast.buoy == .fresh(reading))
    }

    @Test("A months-old buoy reading is reported as stale, not as current")
    func staleBuoyIsFlaggedNotShown() async throws {
        let deadBuoy = BuoyObservation(
            stationID: "shikmona",
            observedAt: Date.utc(2026, 1, 9, 21, 0),
            significantWaveHeightMeters: 4.09,
            peakPeriodSeconds: 11.1
        )
        let repository = ForecastRepository(
            primary: StubForecastSource(samples: series()),
            observations: StubObservationSource(observation: deadBuoy),
            clock: { [now] in now }
        )

        let forecast = try await repository.forecast(for: spot, profile: profile)

        guard case .stale(let reading, let age) = forecast.buoy else {
            Issue.record("expected a stale buoy status, got \(forecast.buoy)")
            return
        }
        #expect(reading.significantWaveHeightMeters == 4.09)
        #expect(age > 30 * 24 * 3600)
    }

    @Test("A dead buoy does not blank the forecast")
    func buoyFailureDegradesOnlyItsOwnSection() async throws {
        let repository = ForecastRepository(
            primary: StubForecastSource(samples: series()),
            observations: StubObservationSource(observation: nil),
            clock: { [now] in now }
        )

        let forecast = try await repository.forecast(for: spot, profile: profile)
        #expect(forecast.buoy == .unavailable)
        #expect(!forecast.hours.isEmpty)
    }

    @Test("A failing ensemble source costs the confidence figure, not the forecast")
    func ensembleFailureDegradesGracefully() async throws {
        let repository = ForecastRepository(
            primary: StubForecastSource(samples: series()),
            ensemble: StubEnsembleSource(error: SourceError.badStatus(402)),
            clock: { [now] in now }
        )

        let forecast = try await repository.forecast(for: spot, profile: profile)
        #expect(forecast.confidence == nil)
        #expect(!forecast.hours.isEmpty)
    }

    @Test("A failing primary source does fail the request")
    func primaryFailurePropagates() async {
        let repository = ForecastRepository(
            primary: StubForecastSource(error: SourceError.badStatus(500)),
            clock: { [now] in now }
        )
        await #expect(throws: SourceError.badStatus(500)) {
            _ = try await repository.forecast(for: spot, profile: profile)
        }
    }

    @Test("A failed fetch is not cached, so a retry can succeed")
    func failuresAreNotCached() async {
        let repository = ForecastRepository(
            primary: StubForecastSource(error: SourceError.badStatus(500)),
            clock: { [now] in now }
        )
        _ = try? await repository.forecast(for: spot, profile: profile)
        await #expect(throws: SourceError.badStatus(500)) {
            _ = try await repository.forecast(for: spot, profile: profile)
        }
    }

    @Test("Every hour arrives transformed, scored and checked for hazards")
    func hoursAreFullyAssembled() async throws {
        let repository = ForecastRepository(
            primary: StubForecastSource(samples: series(hours: 6)),
            clock: { [now] in now }
        )

        let forecast = try await repository.forecast(for: spot, profile: profile)
        #expect(forecast.hours.count == 6)

        for hour in forecast.hours {
            #expect(hour.conditions.spotID == spot.id)
            #expect(hour.score.sport == .surfing)
            // The raw open-sea value is kept, and the displayed value differs
            // from it — proof the transformation ran.
            #expect(hour.conditions.openSeaHeightMeters == 1.0)
            #expect(hour.conditions.waveHeightMeters != 1.0)
        }
    }
}

@Suite("Model confidence")
struct ModelSpreadTests {
    @Test("Models that agree produce high confidence")
    func agreementIsHighConfidence() {
        let spread = ModelSpread(
            timestamp: .utc(2026, 8, 25, 6),
            waveHeightByModel: ["noaa": 1.00, "icon": 1.02, "ecmwf": 0.98]
        )
        #expect(spread.confidence > 0.9)
    }

    @Test("Models that disagree produce low confidence")
    func divergenceIsLowConfidence() {
        let spread = ModelSpread(
            timestamp: .utc(2026, 8, 25, 6),
            waveHeightByModel: ["noaa": 0.4, "icon": 1.6, "ecmwf": 1.0]
        )
        #expect(spread.confidence < 0.2)
    }

    @Test("A single model yields no confidence at all, rather than perfect confidence")
    func singleModelIsNotConfidence() {
        // Confidence is measured from disagreement. One model cannot disagree
        // with itself, so it must not be allowed to claim certainty.
        let spread = ModelSpread(
            timestamp: .utc(2026, 8, 25, 6),
            waveHeightByModel: ["noaa": 1.0]
        )
        #expect(spread.confidence == 0)
    }
}

@Suite("Best window today")
struct BestWindowTodayTests {
    // Israel runs UTC+3 in August, so 05:00 UTC is 08:00 on the beach.
    private let generatedAt = Date.utc(2026, 8, 25, 5)

    private func hour(_ timestamp: Date, score: Int) -> HourlyForecast {
        HourlyForecast(
            conditions: .fixture(timestamp: timestamp),
            score: MatchScore(value: score, sport: .surfing),
            alerts: []
        )
    }

    private func forecast(_ hours: [HourlyForecast]) -> SpotForecast {
        SpotForecast(
            spot: .fixture(),
            hours: hours,
            buoy: .unavailable,
            confidence: nil,
            generatedAt: generatedAt
        )
    }

    @Test("Tomorrow's better window is not reported as today's")
    func tomorrowIsExcluded() throws {
        // The live smoke test caught this reporting "16:00-10:00" — a window
        // whose start was after its end, because the run crossed midnight.
        let result = forecast([
            hour(.utc(2026, 8, 25, 6), score: 60),
            hour(.utc(2026, 8, 25, 7), score: 62),
            hour(.utc(2026, 8, 26, 6), score: 99)  // tomorrow, and far better
        ])

        let window = try #require(result.bestWindowToday)
        #expect(window.peakScore == 62)
        #expect(window.start < window.end, "a window must not run backwards")
        #expect(window.end <= Date.utc(2026, 8, 25, 8))
    }

    @Test("Hours already past are not recommended")
    func pastHoursAreExcluded() throws {
        // Reported at 08:00 local; the dawn session is over.
        let result = forecast([
            hour(.utc(2026, 8, 25, 2), score: 95),  // 05:00 local — gone
            hour(.utc(2026, 8, 25, 6), score: 55)   // 09:00 local — still available
        ])

        let window = try #require(result.bestWindowToday)
        #expect(window.peakScore == 55)
    }

    @Test("Nothing left today returns nil rather than a stale recommendation")
    func nothingLeftReturnsNil() {
        let result = forecast([
            hour(.utc(2026, 8, 25, 1), score: 90),
            hour(.utc(2026, 8, 25, 2), score: 90)
        ])
        #expect(result.bestWindowToday == nil)
    }

    @Test("A window is never reported with a start after its end")
    func windowsNeverRunBackwards() {
        let hours = (0..<72).map { offset in
            hour(generatedAt.addingTimeInterval(Double(offset) * 3600), score: 80)
        }
        if let window = forecast(hours).bestWindowToday {
            #expect(window.start < window.end)
        }
    }
}

@Suite("Best window")
struct WindowFinderTests {
    private func hour(_ index: Int, score: Int) -> HourlyForecast {
        HourlyForecast(
            conditions: .fixture(timestamp: .utc(2026, 8, 25, index)),
            score: MatchScore(value: score, sport: .surfing),
            alerts: []
        )
    }

    @Test("The longest usable run is chosen")
    func longestRunWins() throws {
        let hours = [
            hour(5, score: 20), hour(6, score: 70), hour(7, score: 80), hour(8, score: 75),
            hour(9, score: 10), hour(10, score: 90), hour(11, score: 15)
        ]
        let window = try #require(WindowFinder.bestWindow(in: hours))

        // 06:00-09:00 (three hours) beats the single higher-scoring 10:00 hour —
        // a surfer needs a session, not a minute.
        #expect(window.start == Date.utc(2026, 8, 25, 6))
        #expect(window.end == Date.utc(2026, 8, 25, 9))
        #expect(window.peakScore == 80)
    }

    @Test("A day with nothing worth surfing returns no window")
    func hopelessDayReturnsNil() {
        // Naming the least-bad hours would send someone driving to a flat sea.
        let hours = (5..<12).map { hour($0, score: 12) }
        #expect(WindowFinder.bestWindow(in: hours) == nil)
    }

    @Test("A run that reaches the end of the day is still closed")
    func trailingRunIsClosed() throws {
        let hours = [hour(5, score: 10), hour(6, score: 80), hour(7, score: 85)]
        let window = try #require(WindowFinder.bestWindow(in: hours))
        #expect(window.start == Date.utc(2026, 8, 25, 6))
        #expect(window.end == Date.utc(2026, 8, 25, 8))
    }

    @Test("An empty series returns no window")
    func emptySeriesReturnsNil() {
        #expect(WindowFinder.bestWindow(in: []) == nil)
    }

    @Test("Days are summarised by their best window, never by an average")
    func dailyWindowsUsePeakNotMean() throws {
        // A day that is glassy at dawn and blown out by noon averages to a
        // number that is wrong at every hour it claims to describe.
        let dawn = (5..<9).map { hour($0, score: 90) }
        let afternoon = (12..<18).map { hour($0, score: 5) }

        let days = WindowFinder.dailyWindows(in: dawn + afternoon)
        let day = try #require(days.first)

        #expect(day.peakScore == 90)
        let window = try #require(day.window)
        #expect(window.start == Date.utc(2026, 8, 25, 5))
    }
}
