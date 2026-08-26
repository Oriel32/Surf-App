import Foundation
import Testing
@testable import SurfCore

/// Succeeds until told to stop, so a screen can be walked from loaded to stale.
private actor ToggleForecastSource: ForecastSource {
    nonisolated let identifier = "toggle"
    private var offline = false
    private let samples: [RawMarineSample]

    init(samples: [RawMarineSample]) {
        self.samples = samples
    }

    func goOffline() {
        offline = true
    }

    func forecast(for spot: Spot) async throws -> [RawMarineSample] {
        if offline { throw SourceError.transport("offline") }
        return samples
    }
}

@Suite("Data state")
struct DataStateTests {
    @Test("A stale value is still a value, and it arrives carrying its age")
    func staleExposesValueAndAge() {
        let state = DataState<Int>.stale(7, age: 2_400)
        #expect(state.value == 7)
        #expect(state.isStale)
        #expect(state.age == 2_400)
    }

    @Test("Loading and failed hold nothing to render")
    func emptyStates() {
        #expect(DataState<Int>.loading.value == nil)
        #expect(DataState<Int>.failed(reason: "boom").value == nil)
        #expect(!DataState<Int>.loaded(1).isStale)
        #expect(DataState<Int>.loaded(1).age == nil)
    }

    @Test("Mapping preserves the state, including the age")
    func mappingPreservesState() {
        #expect(DataState<Int>.loaded(2).map { $0 * 2 } == .loaded(4))
        #expect(DataState<Int>.stale(2, age: 60).map { $0 * 2 } == .stale(4, age: 60))
        #expect(DataState<Int>.loading.map { $0 * 2 } == .loading)
        #expect(DataState<Int>.failed(reason: "x").map { $0 * 2 } == .failed(reason: "x"))
    }

    @Test("Age is spoken in words, because a timestamp makes the user do arithmetic")
    func ageInWords() {
        #expect(TimeInterval(30).ageInWordsHebrew == "עכשיו")
        #expect(TimeInterval(40 * 60).ageInWordsHebrew.contains("40"))
        #expect(TimeInterval(3_600).ageInWordsHebrew == "לפני שעה")
        #expect(TimeInterval(5 * 3_600).ageInWordsHebrew.contains("5"))
        #expect(TimeInterval(86_400).ageInWordsHebrew == "אתמול")
        #expect(TimeInterval(3 * 86_400).ageInWordsHebrew.contains("3"))
    }

    @Test("Hebrew counts one, two and many separately")
    func hebrewDualForms() {
        // The dual is a word of its own, not a numeral plus a noun. Hebrew is
        // the primary locale here, not a translation of the English.
        #expect(TimeInterval(90).ageInWordsHebrew == "לפני דקה")
        #expect(TimeInterval(2 * 60).ageInWordsHebrew == "לפני שתי דקות")
        #expect(TimeInterval(2 * 3_600).ageInWordsHebrew == "לפני שעתיים")
        #expect(TimeInterval(2 * 86_400).ageInWordsHebrew == "לפני יומיים")
    }
}

@Suite("Repository data states")
struct RepositoryStateTests {
    private let spot = Spot.fixture()
    private let profile = UserProfile(sport: .surfing, skill: .intermediate)
    private let start = Date.utc(2026, 8, 25, 6)

    private func samples() -> [RawMarineSample] {
        (0..<12).map { .fixture(timestamp: .utc(2026, 8, 25, $0), waveHeightMeters: 1.0) }
    }

    @Test("A clean fetch is loaded, not stale")
    func cleanFetchIsLoaded() async {
        let repository = ForecastRepository(
            primary: ToggleForecastSource(samples: samples()),
            clock: { [start] in start }
        )

        let state = await repository.forecastState(for: spot, profile: profile)
        guard case .loaded(let forecast) = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(forecast.hours.count == 12)
    }

    @Test("A network failure with a previous forecast behind it is stale, not failed")
    func fallsBackToLastKnownGood() async throws {
        // The bug this prevents: an error screen shown to someone standing on
        // the sand who already had a perfectly usable forecast a moment ago.
        let source = ToggleForecastSource(samples: samples())
        let clock = MovableClock(start)
        let repository = ForecastRepository(primary: source, clock: clock.read)

        _ = try await repository.forecast(for: spot, profile: profile)

        clock.advance(by: 40 * 60)  // past the 30-minute cache TTL
        await source.goOffline()

        let state = await repository.forecastState(for: spot, profile: profile)
        guard case .stale(let forecast, let age) = state else {
            Issue.record("expected .stale, got \(state)")
            return
        }
        #expect(forecast.hours.count == 12)
        #expect(age == 40 * 60)
    }

    @Test("A failure with nothing behind it is failed, never a silently empty screen")
    func failsWhenThereIsNoHistory() async {
        let source = ToggleForecastSource(samples: samples())
        await source.goOffline()
        let repository = ForecastRepository(primary: source, clock: { [start] in start })

        let state = await repository.forecastState(for: spot, profile: profile)
        guard case .failed(let reason) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("Refreshing keeps the fallback; only an explicit discard drops it")
    func invalidateKeepsFallbackByDefault() async throws {
        // Pull-to-refresh on a bad connection must not turn a working screen
        // into an error.
        let source = ToggleForecastSource(samples: samples())
        let clock = MovableClock(start)
        let repository = ForecastRepository(primary: source, clock: clock.read)

        _ = try await repository.forecast(for: spot, profile: profile)
        await repository.invalidate()
        await source.goOffline()

        #expect(await repository.forecastState(for: spot, profile: profile).isStale)

        await repository.invalidate(discardingLastKnownGood: true)
        let state = await repository.forecastState(for: spot, profile: profile)
        guard case .failed = state else {
            Issue.record("expected .failed after an explicit discard, got \(state)")
            return
        }
    }
}
