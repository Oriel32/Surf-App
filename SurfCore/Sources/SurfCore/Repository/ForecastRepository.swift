import Foundation

/// What the buoy layer is currently able to say. Modelled as three explicit
/// cases because "no reading" and "an old reading" are different facts, and
/// collapsing them is how a stale storm value ends up on screen as live.
public enum BuoyStatus: Sendable, Equatable {
    case fresh(BuoyObservation)
    case stale(BuoyObservation, age: TimeInterval)
    case unavailable
}

/// Everything the UI needs for one spot, already transformed, scored and checked.
public struct SpotForecast: Sendable {
    public let spot: Spot
    public let hours: [HourlyForecast]
    public let buoy: BuoyStatus
    /// 0...1 model agreement, or `nil` when no ensemble source was configured.
    public let confidence: Double?
    public let generatedAt: Date

    /// The best remaining window today, in local beach time.
    ///
    /// Two filters, both load-bearing. Without the day filter this searches the
    /// whole multi-day series and cheerfully reports tomorrow's peak under a
    /// "today" heading — with a start time later than its end time, because the
    /// run crosses midnight. Without the forward filter it recommends a dawn
    /// session to someone reading the screen at 20:00.
    ///
    /// Returning `nil` late in the day is the correct answer, not a gap: there
    /// genuinely is nothing left today.
    public var bestWindowToday: SessionWindow? {
        let calendar = Calendar.israelStandard
        let remaining = hours.filter { hour in
            let stamp = hour.conditions.timestamp
            let stillToCome = stamp.addingTimeInterval(3600) > generatedAt
            return stillToCome && calendar.isDate(stamp, inSameDayAs: generatedAt)
        }
        return WindowFinder.bestWindow(in: remaining)
    }
}

/// Fetches, assembles and caches forecasts.
///
/// An `actor` because the cache is genuinely shared mutable state — several
/// screens ask for the same spot at once on launch. Per Apple's guidance actors
/// come last, not first: everything below this layer is pure functions, and this
/// is the only place in SurfCore that needs serialised access.
public actor ForecastRepository {
    private let primary: any ForecastSource
    private let ensemble: (any ModelEnsembleSource)?
    private let observations: (any ObservationSource)?
    private let clock: @Sendable () -> Date
    private let cacheTTL: TimeInterval
    private let maxObservationAge: TimeInterval

    private enum CacheEntry {
        case inProgress(Task<SpotForecast, Error>)
        case ready(SpotForecast, cachedAt: Date)
    }

    private var cache: [String: CacheEntry] = [:]

    /// - Parameters:
    ///   - cacheTTL: model runs land on fixed cycles (00Z/12Z) and buoys update
    ///     hourly, so refetching more often than this buys nothing and, for
    ///     Stormglass, burns a request budget of about ten calls a day.
    ///   - clock: injected so cache expiry and staleness are testable without
    ///     waiting for real time to pass.
    public init(
        primary: any ForecastSource,
        ensemble: (any ModelEnsembleSource)? = nil,
        observations: (any ObservationSource)? = nil,
        cacheTTL: TimeInterval = 30 * 60,
        maxObservationAge: TimeInterval = 3 * 3600,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.primary = primary
        self.ensemble = ensemble
        self.observations = observations
        self.cacheTTL = cacheTTL
        self.maxObservationAge = maxObservationAge
        self.clock = clock
    }

    public func forecast(for spot: Spot, profile: UserProfile) async throws -> SpotForecast {
        let key = "\(spot.id)|\(profile.sport.rawValue)|\(profile.skill.rawValue)"

        if let entry = cache[key] {
            switch entry {
            case .ready(let forecast, let cachedAt):
                if clock().timeIntervalSince(cachedAt) < cacheTTL { return forecast }
            case .inProgress(let task):
                // Concurrent callers for the same spot share one network call
                // rather than racing. Critical on a provider capped at ~10
                // requests per day.
                return try await task.value
            }
        }

        let task = Task { try await self.build(spot: spot, profile: profile) }
        cache[key] = .inProgress(task)  // stored synchronously — no interleaving before this

        do {
            let forecast = try await task.value
            cache[key] = .ready(forecast, cachedAt: clock())
            return forecast
        } catch {
            cache[key] = nil  // allow a retry after failure
            throw error
        }
    }

    public func invalidate() {
        cache.removeAll()
    }

    // MARK: - Assembly

    private func build(spot: Spot, profile: UserProfile) async throws -> SpotForecast {
        // The forecast is required; the other two are credibility extras and
        // must never be able to fail the whole screen.
        async let samplesTask = primary.forecast(for: spot)
        async let confidenceTask = bestEffortConfidence(for: spot)
        async let buoyTask = bestEffortObservation(for: spot)

        let samples = try await samplesTask

        let hours = samples.map { sample -> HourlyForecast in
            let conditions = WaveTransform.transform(sample, at: spot)
            return HourlyForecast(
                conditions: conditions,
                score: MatchScoreEngine.score(for: conditions, profile: profile),
                alerts: SafetyEngine.alerts(for: conditions, profile: profile)
            )
        }

        return SpotForecast(
            spot: spot,
            hours: hours,
            buoy: await buoyTask,
            confidence: await confidenceTask,
            generatedAt: clock()
        )
    }

    private func bestEffortConfidence(for spot: Spot) async -> Double? {
        guard let ensemble else { return nil }
        guard let spreads = try? await ensemble.ensemble(for: spot), !spreads.isEmpty else {
            return nil
        }
        // Near-term agreement is what the user is deciding on today.
        let horizon = spreads.prefix(24)
        return horizon.map(\.confidence).reduce(0, +) / Double(horizon.count)
    }

    private func bestEffortObservation(for spot: Spot) async -> BuoyStatus {
        guard let observations, let stationID = spot.buoyStationID else { return .unavailable }
        guard let reading = try? await observations.latestObservation(stationID: stationID) else {
            return .unavailable
        }

        let now = clock()
        if reading.isFresh(asOf: now, maxAge: maxObservationAge) {
            return .fresh(reading)
        }
        // Deliberately surfaced rather than dropped: "the buoy is offline" is
        // useful information, and it is the only way the UI can avoid showing a
        // months-old storm reading as the current sea.
        return .stale(reading, age: reading.age(asOf: now))
    }
}
