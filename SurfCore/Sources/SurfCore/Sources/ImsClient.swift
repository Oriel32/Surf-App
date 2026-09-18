import Foundation

/// Measured coastal wind from the Israel Meteorological Service (IMS).
///
/// The fourth source, and the only one that measures the parameter the safety
/// alert turns on. Open-Meteo's wind is a 9 km grid cell averaged over an hour;
/// this is a mast on the coast, reporting every ten minutes. Where ISRAMAR gives
/// the wave model a witness, this gives the wind model one.
///
/// ## Two verified traps
/// 1. **Timestamps are local *standard* time all year, and the `+03:00` suffix
///    is wrong for half of it.** Verified live on 2026-09-18: the payload read
///    `2026-09-18T10:50:00+03:00` when the actual local time was 09:10 IDT.
///    Taken literally that reading is 1 h 20 min old and permanently fails any
///    freshness gate; read as local standard time it is 08:50 UTC, twenty
///    minutes old, which is what a ten-minute cadence should produce. So the
///    offset in the string is discarded and `imsStandardOffsetSeconds` is
///    applied instead. See `DateParsing.makeIMSFormatter`.
/// 2. **A value can be present, numeric and invalid.** Elat (station 64) served
///    `WS: 0.0` with `status: 2, valid: false` for all 65 of its slices that same
///    day: the anemometer is dead. A decoder that reads `value` without checking
///    the flags reports dead calm at Eilat — in the one basin where wind *is*
///    the wave model. Both flags are checked, every time.
///
/// Auth is `Authorization: ApiToken <token>`, and every endpoint — station
/// metadata included — answers 401 without it.
public struct ImsClient: WindObservationSource {
    public let identifier = "ims"

    /// A weather station: its IMS id, where it is, and what to call it in Hebrew.
    ///
    /// Only coastal stations appear here. The nearest station to a beach is
    /// frequently the wrong one: Haifa's two nearest masts sit on the Carmel
    /// ridge hundreds of metres up, and Bet Dagan is inland of Bat Yam. Ridge and
    /// inland wind is a different wind, and the sea breeze is a coastal
    /// phenomenon.
    public struct Station: Sendable, Equatable {
        public let id: String
        public let nameHebrew: String
        public let latitude: Double
        public let longitude: Double
    }

    /// Verified against `/v1/envista/stations` on 2026-09-18: active, and
    /// reporting WS, WD and WSmax.
    public static let stations: [String: Station] = [
        "hadera-port": Station(
            id: "46", nameHebrew: "נמל חדרה",
            latitude: 32.4732, longitude: 34.8815
        ),
        "tel-aviv-coast": Station(
            id: "178", nameHebrew: "חוף תל אביב",
            latitude: 32.0580, longitude: 34.7588
        ),
        "ashdod-port": Station(
            id: "124", nameHebrew: "נמל אשדוד",
            latitude: 31.8342, longitude: 34.6377
        ),
        "ashqelon-port": Station(
            id: "208", nameHebrew: "נמל אשקלון",
            latitude: 31.6394, longitude: 34.5215
        ),
        // The only station in the Gulf of Eilat, and its anemometer is dead:
        // every slice on 2026-09-18 carried `status: 2, valid: false`. Kept
        // because it is the only candidate that basin has, and because the
        // validity gate turns it into an honest "no reading" rather than a
        // fabricated calm. Air temperature there is still valid.
        "elat": Station(
            id: "64", nameHebrew: "אילת",
            latitude: 29.5526, longitude: 34.9520
        )
    ]

    /// Where a station sits relative to a spot, so the reading can be shown with
    /// the distance that makes it honest.
    public static func reference(for station: Station, from spot: Spot) -> StationReference {
        StationReference(
            stationID: station.id,
            nameHebrew: station.nameHebrew,
            distanceKilometres: Geo.distanceKilometres(
                fromLatitude: spot.latitude, longitude: spot.longitude,
                toLatitude: station.latitude, longitude: station.longitude
            ),
            bearingDegrees: Geo.bearingDegrees(
                fromLatitude: spot.latitude, longitude: spot.longitude,
                toLatitude: station.latitude, longitude: station.longitude
            ),
            instrumentHebrew: "תחנת"
        )
    }

    private static let baseURL = "https://api.ims.gov.il/v1/envista/stations"

    private let token: String
    private let transport: any HTTPTransport

    /// - Parameter token: requested by email from IMS. Read it from the
    ///   environment or a gitignored file — never commit it, and never let it
    ///   reach a URL, a log line or the calibration ledger.
    public init(token: String, transport: (any HTTPTransport)? = nil) {
        self.token = token
        // The 10-minute policy matches the station cadence exactly, so a screen
        // full of spots sharing one station hits the network once. The cache is
        // keyed on the URL alone and the token travels in a header, so the token
        // never becomes part of a cache key.
        self.transport = transport ?? CachingTransport(
            wrapping: RetryingTransport(wrapping: URLSessionTransport()),
            policy: .hourlyObservation
        )
    }

    private var headers: [String: String] {
        ["Authorization": "ApiToken \(token)"]
    }

    public func latestWind(stationID: String) async throws -> WindObservation {
        let station = try Self.station(stationID)
        guard let url = URL(string: "\(Self.baseURL)/\(station.id)/data/latest") else {
            throw SourceError.transport("Could not build IMS URL for \(stationID)")
        }
        let data = try await transport.data(from: url, headers: headers)
        guard let reading = try Self.parse(data, stationID: stationID).first else {
            throw SourceError.malformedPayload("ims: \(stationID) returned no records")
        }
        return reading
    }

    /// The reading nearest a past moment, for checking the engine against a field
    /// report that has already happened.
    ///
    /// The buoy cannot do this — ISRAMAR serves only its latest value — which is
    /// why `smoke --at` could previously compare a past model hour against
    /// nothing at all.
    ///
    /// The gust is taken as the highest `WSmax` in the hour *ending* at the
    /// requested time, because that is what the model's hourly gust means. The
    /// mean comes from the nearest slice alone.
    public func wind(stationID: String, near moment: Date) async throws -> WindObservation {
        let station = try Self.station(stationID)
        let day = DateParsing.imsDayPath(for: moment)
        guard let url = URL(string: "\(Self.baseURL)/\(station.id)/data/daily/\(day)") else {
            throw SourceError.transport("Could not build IMS URL for \(stationID)")
        }
        let data = try await transport.data(from: url, headers: headers)
        let readings = try Self.parse(data, stationID: stationID)
        return try Self.nearest(to: moment, in: readings)
    }

    static func station(_ stationID: String) throws -> Station {
        guard let station = stations[stationID] else {
            throw SourceError.unknownStation(stationID)
        }
        return station
    }

    /// The slice nearest `moment`, carrying the hour's peak gust.
    static func nearest(to moment: Date, in readings: [WindObservation]) throws -> WindObservation {
        guard let closest = readings.min(by: {
            abs($0.observedAt.timeIntervalSince(moment)) < abs($1.observedAt.timeIntervalSince(moment))
        }) else {
            throw SourceError.malformedPayload("ims: no usable records in range")
        }

        let hourGust = readings
            .filter {
                let delta = closest.observedAt.timeIntervalSince($0.observedAt)
                return delta >= 0 && delta < 3600
            }
            .compactMap(\.windGustMPS)
            .max()

        return WindObservation(
            stationID: closest.stationID,
            observedAt: closest.observedAt,
            windSpeedMPS: closest.windSpeedMPS,
            windDirectionDegrees: closest.windDirectionDegrees,
            windGustMPS: hourGust ?? closest.windGustMPS,
            airTemperatureC: closest.airTemperatureC
        )
    }

    /// Parsing is `static` and pure so both traps above are tested against
    /// checked-in payloads, with no network and no clock.
    ///
    /// Records whose wind is flagged invalid are dropped rather than zeroed. An
    /// empty result therefore means "this station is not measuring wind", which
    /// is a true statement about Elat today and a far better one than 0.0 m/s.
    static func parse(_ data: Data, stationID: String) throws -> [WindObservation] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw SourceError.malformedPayload("ims: \(error)")
        }

        let formatter = DateParsing.makeIMSFormatter()

        let readings = try payload.data.compactMap { record -> WindObservation? in
            guard let observedAt = DateParsing.imsDate(from: record.datetime, using: formatter) else {
                throw SourceError.malformedPayload("ims: unparseable datetime '\(record.datetime)'")
            }

            // Channel *ids* differ between stations for the same parameter — the
            // IMS documentation highlights this in yellow — so every lookup goes
            // by name, and only a value the station itself calls good is used.
            func value(named name: String) -> Double? {
                guard let channel = record.channels.first(where: { $0.name == name }) else { return nil }
                guard channel.status == 1, channel.valid else { return nil }
                return channel.value
            }

            guard let speed = value(named: "WS"), let direction = value(named: "WD") else {
                return nil
            }

            return WindObservation(
                stationID: stationID,
                observedAt: observedAt,
                windSpeedMPS: speed,
                windDirectionDegrees: direction,
                windGustMPS: value(named: "WSmax"),
                airTemperatureC: value(named: "TD")
            )
        }

        guard !readings.isEmpty else {
            throw SourceError.malformedPayload(
                "ims: \(stationID) reported no valid WS/WD — the station's own flags say the sensor is bad"
            )
        }
        return readings
    }

    /// `{"data": [{"datetime": "2026-09-18T10:50:00+03:00",
    ///             "channels": [{"id": 4, "name": "WS", "value": 8.2,
    ///                           "status": 1, "valid": true}]}],
    ///   "stationId": 178}`
    private struct Payload: Decodable {
        struct Record: Decodable {
            struct Channel: Decodable {
                let name: String
                let value: Double?
                /// 1 good, 2 bad. Both this and `valid` are checked: Elat serves
                /// `status: 2, valid: false, value: 0.0`.
                let status: Int
                let valid: Bool
            }
            let datetime: String
            let channels: [Channel]
        }
        let data: [Record]
    }
}
