import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wraps any `HTTPTransport` and holds on to what it fetched.
///
/// ## Why this exists
/// Sources refresh on their own cadence and refetching faster than that buys
/// nothing: the global models land on fixed 00Z/12Z runs and the buoys update
/// hourly. Caching per view instead of per cadence is the mistake this type
/// exists to make impossible.
///
/// For Stormglass it is not an optimisation but a survival constraint. The free
/// tier is roughly **ten requests a day**, so an uncached client is one pull-to-
/// refresh away from having no confidence engine until midnight.
///
/// ## Where it sits
/// It composes with the retry decorator, and the order matters:
///
/// ```swift
/// CachingTransport(wrapping: RetryingTransport(wrapping: URLSessionTransport()))
/// ```
///
/// Caching outermost means a cache hit costs nothing at all, and a retried
/// request is stored once under the URL that finally succeeded. Inverting the
/// two would retry around the cache and re-issue requests that were already
/// answered.
///
/// ## What it deliberately does not do
/// - **It does not cache failures.** A refused request must be retryable
///   immediately; caching an error would turn one bad minute into a bad hour.
/// - **It does not serve stale data on error.** Deciding to show a user an old
///   forecast is a product judgement with an age label attached, and it belongs
///   to `ForecastRepository`, which has the timestamps to label it honestly. A
///   transport that silently served expired bytes would take that decision away
///   from the layer that can explain it.
///
/// ## Known limitation
/// The cache key is the URL alone, so headers are not part of the identity. That
/// is deliberate: the only header in use here is the Stormglass credential, and
/// keying a cache on a secret is worse than the aliasing it would prevent. One
/// process talking to one endpoint with two different API keys would collide,
/// which does not happen in this app.
public struct CachingTransport: HTTPTransport {
    public struct Policy: Sendable {
        public let timeToLive: TimeInterval

        public init(timeToLive: TimeInterval) {
            precondition(timeToLive >= 0, "A cache TTL cannot be negative")
            self.timeToLive = timeToLive
        }

        /// One hour. Open-Meteo publishes on fixed model cycles, so a shorter
        /// window returns the same bytes over a slower path.
        public static let modelRun = Policy(timeToLive: 60 * 60)

        /// Ten minutes. ISRAMAR updates hourly; this is short enough to pick up
        /// a new reading promptly and long enough that a screen full of spots
        /// sharing one buoy hits the network once.
        public static let hourlyObservation = Policy(timeToLive: 10 * 60)

        /// Six hours, for Stormglass.
        ///
        /// A backstop, not a substitute for the scheduled server-side job: at
        /// roughly ten requests a day this budget cannot cover the spot list
        /// from a device however long the TTL is. It exists so that a device
        /// that does call the API cannot burn the day's allowance in a minute.
        public static let rateLimited = Policy(timeToLive: 6 * 60 * 60)
    }

    private let wrapped: any HTTPTransport
    private let store: Store

    /// - Parameter clock: injected so expiry is testable without waiting through it.
    public init(
        wrapping wrapped: any HTTPTransport,
        policy: Policy = .modelRun,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.wrapped = wrapped
        self.store = Store(timeToLive: policy.timeToLive, clock: clock)
    }

    public func data(from url: URL, headers: [String: String]) async throws -> Data {
        let wrapped = self.wrapped
        return try await store.data(for: url) {
            try await wrapped.data(from: url, headers: headers)
        }
    }

    /// Drops everything held. For pull-to-refresh, where the user is explicitly
    /// asking to pay the network cost again.
    public func invalidate() async {
        await store.removeAll()
    }

    /// Number of entries currently held. Exposed for tests and diagnostics.
    public var count: Int {
        get async { await store.count }
    }
}

/// The mutable half, isolated in an actor because several screens ask for the
/// same spot at once on launch.
private actor Store {
    private enum Entry {
        case ready(Data, at: Date)
        case inFlight(Task<Data, Error>)
    }

    private let timeToLive: TimeInterval
    private let clock: @Sendable () -> Date
    private var entries: [URL: Entry] = [:]

    init(timeToLive: TimeInterval, clock: @escaping @Sendable () -> Date) {
        self.timeToLive = timeToLive
        self.clock = clock
    }

    var count: Int { entries.count }

    func removeAll() {
        entries.removeAll()
    }

    func data(
        for url: URL,
        fetch: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let entry = entries[url] {
            switch entry {
            case .ready(let data, let storedAt):
                if clock().timeIntervalSince(storedAt) < timeToLive { return data }
            case .inFlight(let task):
                // Concurrent callers for the same URL share one request rather
                // than racing. On a ten-a-day budget this is the difference
                // between one call and one per visible spot.
                return try await task.value
            }
        }

        let task = Task { try await fetch() }
        // Stored synchronously, before any suspension point, so a second caller
        // arriving in the same tick finds the task rather than starting another.
        entries[url] = .inFlight(task)

        do {
            let data = try await task.value
            entries[url] = .ready(data, at: clock())
            sweepExpired()
            return data
        } catch {
            entries[url] = nil
            throw error
        }
    }

    /// Keeps the table from growing without bound over a long session. Only runs
    /// on a store, which is rare compared to a hit.
    private func sweepExpired() {
        let now = clock()
        entries = entries.filter { _, entry in
            switch entry {
            case .inFlight: return true
            case .ready(_, let storedAt): return now.timeIntervalSince(storedAt) < timeToLive
            }
        }
    }
}
