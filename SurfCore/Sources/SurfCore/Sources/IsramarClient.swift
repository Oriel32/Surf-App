import Foundation

/// Ground truth from Israel's national oceanographic institute (IOLR).
///
/// ## This is scraped JSON, not an API
/// There is no documentation, no versioning, no SLA and no stability guarantee.
/// The endpoints below were verified by hand against the live site; treat every
/// one of them as liable to change or vanish without notice. A failure here must
/// never degrade the forecast path — it is a bonus layer of credibility, not a
/// dependency.
///
/// ## A 200 is not evidence of fresh data
/// The Shikmona endpoint has been returning HTTP 200 with a reading frozen at
/// 2026-01-09 for months, because the buoy is offline but the file is still
/// served. Rendering that 4.09 m storm reading as "live now" during a flat
/// August afternoon would be the worst bug this app could ship. Freshness is
/// therefore decided from the payload's own `datetime` field and nowhere else —
/// see `BuoyObservation.isFresh(asOf:maxAge:)`.
public struct IsramarClient: ObservationSource {
    public let identifier = "isramar"

    /// Station id → filename. The casing really is inconsistent between
    /// stations on the live server; these strings are verified, not guessed.
    public static let stationFiles: [String: String] = [
        "hadera": "Hadera_Hs_Per",       // verified live, hourly
        "shikmona": "ShikBuoy_HS_Per"    // verified stale since 2026-01-09
    ]

    private static let baseURL = "https://isramar.ocean.org.il/isramar2009/station/data"

    private let transport: any HTTPTransport

    public init(transport: (any HTTPTransport)? = nil) {
        // A retry here is cheap and this endpoint is unmanaged scraped JSON, but
        // the forecast never waits on it: `ForecastRepository` treats a failure
        // as `.unavailable` either way.
        self.transport = transport ?? RetryingTransport(wrapping: URLSessionTransport())
    }

    public func latestObservation(stationID: String) async throws -> BuoyObservation {
        guard let file = Self.stationFiles[stationID] else {
            throw SourceError.unknownStation(stationID)
        }
        guard let url = URL(string: "\(Self.baseURL)/\(file).json") else {
            throw SourceError.transport("Could not build ISRAMAR URL for \(stationID)")
        }

        let data = try await transport.data(from: url, headers: [:])
        return try Self.parse(data, stationID: stationID)
    }

    /// Parsing is `static` and pure so the staleness behaviour can be tested
    /// against a fixture without a network or a live buoy.
    static func parse(_ data: Data, stationID: String) throws -> BuoyObservation {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw SourceError.malformedPayload("isramar: \(error)")
        }

        let formatter = DateParsing.makeUTCFormatter(DateParsing.isramarFormat)
        guard let observedAt = formatter.date(from: payload.datetime) else {
            throw SourceError.malformedPayload("isramar: unparseable datetime '\(payload.datetime)'")
        }

        // Match on the human-readable names the endpoint actually uses; there
        // are no stable machine keys to rely on.
        func value(named name: String) -> Double? {
            payload.parameters.first { $0.name == name }?.values.first ?? nil
        }

        guard let height = value(named: "Significant wave height"),
              let period = value(named: "Peak wave period")
        else {
            throw SourceError.malformedPayload("isramar: missing Hs/Tp for \(stationID)")
        }

        return BuoyObservation(
            stationID: stationID,
            observedAt: observedAt,
            significantWaveHeightMeters: height,
            peakPeriodSeconds: period,
            maximumWaveHeightMeters: value(named: "Maximal wave height")
        )
    }

    /// `{"datetime": "2026-08-25 16:00 UTC",
    ///   "parameters": [{"name": "...", "units": "m", "values": [0.66]}]}`
    private struct Payload: Decodable {
        struct Parameter: Decodable {
            let name: String
            let units: String?
            let values: [Double?]
        }
        let datetime: String
        let parameters: [Parameter]
    }
}
