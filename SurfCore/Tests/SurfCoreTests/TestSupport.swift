import Foundation
@testable import SurfCore

// MARK: - Fixtures

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error { case missing(String) }
}

/// Serves canned payloads so the ingest layer is testable with no network.
///
/// `error` is a concrete `SourceError` rather than `any Error`, because an
/// existential `Error` is not Sendable and `HTTPTransport` requires it.
struct StubTransport: HTTPTransport {
    let payload: Data
    var error: SourceError? = nil

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        if let error { throw error }
        return payload
    }
}

// MARK: - Builders

extension Date {
    /// UTC wall-clock construction, so tests never depend on the machine's zone.
    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)!
    }
}

extension Spot {
    /// A generic west-facing Israeli beach break.
    static func fixture(
        id: String = "test-spot",
        exposureCoefficient: Double = 0.85,
        shorelineNormalDegrees: Double = 270,
        breakDepthMeters: Double = 2.0,
        basin: Basin = .mediterranean,
        buoyStationID: String? = nil
    ) -> Spot {
        Spot(
            id: id,
            nameHebrew: "חוף בדיקה",
            nameEnglish: "Test Beach",
            latitude: 32.087,
            longitude: 34.769,
            basin: basin,
            exposureCoefficient: exposureCoefficient,
            shorelineNormalDegrees: shorelineNormalDegrees,
            breakDepthMeters: breakDepthMeters,
            buoyStationID: buoyStationID
        )
    }
}

extension RawMarineSample {
    static func fixture(
        timestamp: Date = .utc(2026, 8, 25, 6),
        waveHeightMeters: Double = 1.0,
        wavePeriodSeconds: Double = 8.0,
        waveDirectionDegrees: Double = 270,
        windSpeedMPS: Double = 3.0,
        windDirectionDegrees: Double = 90
    ) -> RawMarineSample {
        RawMarineSample(
            timestamp: timestamp,
            waveHeightMeters: waveHeightMeters,
            wavePeriodSeconds: wavePeriodSeconds,
            waveDirectionDegrees: waveDirectionDegrees,
            windSpeedMPS: windSpeedMPS,
            windDirectionDegrees: windDirectionDegrees
        )
    }
}

extension SpotConditions {
    static func fixture(
        waveHeightMeters: Double = 0.8,
        periodSeconds: Double = 8,
        windSpeedMPS: Double = 3,
        windRelation: WindRelation = .offshore,
        seaState: SeaState = .glassy,
        timestamp: Date = .utc(2026, 8, 25, 6)
    ) -> SpotConditions {
        SpotConditions(
            timestamp: timestamp,
            spotID: "test-spot",
            waveHeightMeters: waveHeightMeters,
            periodSeconds: periodSeconds,
            band: WaveBand.band(forHeightMeters: waveHeightMeters),
            seaState: seaState,
            windSpeedMPS: windSpeedMPS,
            windDirectionDegrees: 90,
            windRelation: windRelation,
            openSeaHeightMeters: waveHeightMeters * 1.2,
            isSynthetic: false
        )
    }
}

/// Knots are far more readable than m/s in scoring assertions.
func mps(knots: Double) -> Double {
    Units.metersPerSecond(fromKnots: knots)
}

/// A clock the test can wind forward, so cache expiry and staleness are
/// exercised without waiting through them in real time.
///
/// A locked class rather than an actor: `CachingTransport` and
/// `ForecastRepository` both take a synchronous `@Sendable () -> Date`, and an
/// actor's state cannot be read from one.
final class MovableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        self.current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }

    /// Handed to the type under test.
    var read: @Sendable () -> Date {
        { self.now }
    }
}
