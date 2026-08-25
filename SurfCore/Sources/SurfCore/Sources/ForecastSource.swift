import Foundation

// On Linux and Windows, swift-corelibs-foundation splits URLSession into its own
// module. Only `URLSessionTransport` needs it — everything else in SurfCore is
// plain Swift, which is what lets the engine and its tests build off-Mac.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The network seam. Every client takes one of these, so the whole ingest layer
/// is testable against checked-in fixture payloads with no network and no clock.
public protocol HTTPTransport: Sendable {
    func data(from url: URL, headers: [String: String]) async throws -> Data
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    public func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SourceError.badStatus(http.statusCode)
        }
        return data
    }
}

public enum SourceError: Error, Equatable, Sendable {
    case badStatus(Int)
    case transport(String)
    case malformedPayload(String)
    case unknownStation(String)
    /// The payload parsed fine and the data in it is too old to show.
    /// ISRAMAR serves months-old readings with HTTP 200, so this is a normal
    /// outcome, not an exceptional one.
    case staleObservation(ageSeconds: TimeInterval)
}

/// A source that produces an hourly forecast series.
///
/// Deliberately narrow: not every provider does this. ISRAMAR measures the
/// present and forecasts nothing, so it conforms to `ObservationSource` instead
/// rather than being forced into a shape it cannot fill.
public protocol ForecastSource: Sendable {
    var identifier: String { get }
    func forecast(for spot: Spot) async throws -> [RawMarineSample]
}

/// A source that reports several independent models separately, so their
/// disagreement can be measured.
public protocol ModelEnsembleSource: Sendable {
    func ensemble(for spot: Spot) async throws -> [ModelSpread]
}

/// A source of real measurements from real instruments.
public protocol ObservationSource: Sendable {
    func latestObservation(stationID: String) async throws -> BuoyObservation
}

/// Date formatters are handed out as fresh instances rather than shared statics.
///
/// `DateFormatter` and `ISO8601DateFormatter` are classes with mutable state and
/// are not `Sendable`, so a `static let` of one is a data race the Swift 6
/// compiler rejects outright. Silencing that with `nonisolated(unsafe)` would be
/// annotating a real hazard away; instead each caller builds one formatter and
/// reuses it across its own loop, which keeps the per-parse cost off the hot path
/// without sharing anything across tasks.
enum DateParsing {
    /// Open-Meteo, with `timezone=UTC`: "2026-08-25T16:00".
    static let openMeteoFormat = "yyyy-MM-dd'T'HH:mm"

    /// ISRAMAR: "2026-08-25 16:00 UTC".
    static let isramarFormat = "yyyy-MM-dd HH:mm 'UTC'"

    static func makeUTCFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    /// Stormglass: ISO-8601 with offset.
    static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
