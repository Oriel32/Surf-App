import Foundation
import Testing
@testable import SurfCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Counts how often the network was actually reached, and can be told to fail
/// its first few attempts.
private actor CountingTransport: HTTPTransport {
    private(set) var calls = 0
    private let payload: Data
    private let failFirst: Int
    private let delay: Duration?

    init(payload: Data = Data("ok".utf8), failFirst: Int = 0, delay: Duration? = nil) {
        self.payload = payload
        self.failFirst = failFirst
        self.delay = delay
    }

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        calls += 1
        if calls <= failFirst { throw SourceError.transport("dropped") }
        if let delay { try await Task.sleep(for: delay) }
        return payload
    }

    var callCount: Int { calls }
}

@Suite("Transport caching")
struct CachingTransportTests {
    private let url = URL(string: "https://example.test/marine")!
    private let other = URL(string: "https://example.test/weather")!
    private let start = Date.utc(2026, 8, 25, 6)

    @Test("A second request inside the TTL never reaches the network")
    func servesFromCache() async throws {
        let network = CountingTransport()
        let cache = CachingTransport(wrapping: network, policy: .modelRun)

        _ = try await cache.data(from: url, headers: [:])
        let second = try await cache.data(from: url, headers: [:])

        #expect(String(decoding: second, as: UTF8.self) == "ok")
        #expect(await network.callCount == 1)
    }

    @Test("Once the TTL expires the source is asked again")
    func refetchesAfterExpiry() async throws {
        let network = CountingTransport()
        let clock = MovableClock(start)
        let cache = CachingTransport(
            wrapping: network, policy: .hourlyObservation, clock: clock.read
        )

        _ = try await cache.data(from: url, headers: [:])
        clock.advance(by: CachingTransport.Policy.hourlyObservation.timeToLive - 1)
        _ = try await cache.data(from: url, headers: [:])
        #expect(await network.callCount == 1)

        clock.advance(by: 2)
        _ = try await cache.data(from: url, headers: [:])
        #expect(await network.callCount == 2)
    }

    @Test("Concurrent requests for the same URL share one call")
    func coalescesConcurrentRequests() async throws {
        // On a ten-requests-a-day budget this is the difference between one call
        // and one per visible spot.
        let network = CountingTransport(delay: .milliseconds(40))
        let cache = CachingTransport(wrapping: network)

        async let first = cache.data(from: url, headers: [:])
        async let second = cache.data(from: url, headers: [:])
        async let third = cache.data(from: url, headers: [:])
        _ = try await (first, second, third)

        #expect(await network.callCount == 1)
    }

    @Test("A failure is not cached, so the next request can succeed")
    func doesNotCacheFailures() async throws {
        // Caching an error would turn one bad minute into a bad hour.
        let network = CountingTransport(failFirst: 1)
        let cache = CachingTransport(wrapping: network)

        await #expect(throws: SourceError.self) {
            _ = try await cache.data(from: url, headers: [:])
        }
        let recovered = try await cache.data(from: url, headers: [:])

        #expect(String(decoding: recovered, as: UTF8.self) == "ok")
        #expect(await network.callCount == 2)
    }

    @Test("Different URLs are cached separately")
    func keysByURL() async throws {
        let network = CountingTransport()
        let cache = CachingTransport(wrapping: network)

        _ = try await cache.data(from: url, headers: [:])
        _ = try await cache.data(from: other, headers: [:])
        _ = try await cache.data(from: url, headers: [:])

        #expect(await network.callCount == 2)
        #expect(await cache.count == 2)
    }

    @Test("Invalidating drops everything held")
    func invalidateForcesRefetch() async throws {
        let network = CountingTransport()
        let cache = CachingTransport(wrapping: network)

        _ = try await cache.data(from: url, headers: [:])
        await cache.invalidate()
        _ = try await cache.data(from: url, headers: [:])

        #expect(await network.callCount == 2)
        #expect(await cache.count == 1)
    }

    @Test("Caching outside retrying stores the result the retries earned")
    func composesWithRetry() async throws {
        // The composition the clients actually use. A request that needed three
        // attempts is stored once, and the next caller pays nothing.
        let network = CountingTransport(failFirst: 2)
        let cache = CachingTransport(
            wrapping: RetryingTransport(wrapping: network, policy: .standard) { _ in }
        )

        _ = try await cache.data(from: url, headers: [:])
        _ = try await cache.data(from: url, headers: [:])

        #expect(await network.callCount == 3)
    }

    @Test("Expired entries are swept rather than accumulating for the session")
    func sweepsExpiredEntries() async throws {
        let network = CountingTransport()
        let clock = MovableClock(start)
        let cache = CachingTransport(
            wrapping: network, policy: .hourlyObservation, clock: clock.read
        )

        _ = try await cache.data(from: url, headers: [:])
        clock.advance(by: CachingTransport.Policy.hourlyObservation.timeToLive + 1)
        _ = try await cache.data(from: other, headers: [:])

        #expect(await cache.count == 1)
    }
}
