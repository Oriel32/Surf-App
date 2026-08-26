import Foundation

/// The confidence engine.
///
/// Stormglass returns each parameter broken down **by source model** — NOAA,
/// ICON, ECMWF, Météo-France — in a single response. That per-model breakdown is
/// the entire reason this provider is here: the spread between independent
/// models *is* the confidence metric. A confidence percentage derived from one
/// model is a fabrication, and this app does not ship one.
///
/// ## Rate limit
/// The free tier allows roughly **10 requests per day**. This client must not be
/// called per-view or per-device. Call it from a scheduled server-side job for a
/// fixed spot list and cache the result; `ForecastRepository` assumes exactly
/// that and will not hammer it.
public struct StormglassClient: ForecastSource, ModelEnsembleSource {
    public let identifier = "stormglass"

    private let transport: any HTTPTransport
    private let apiKey: String
    private let models: [String]

    /// - Parameter apiKey: read from the environment or the keychain. Never
    ///   commit it, and never bake it into the app binary for a free-tier key.
    public init(
        apiKey: String,
        transport: (any HTTPTransport)? = nil,
        models: [String] = ["noaa", "icon", "meteo", "ecmwf"]
    ) {
        self.apiKey = apiKey
        // `.frugal`, not `.standard`: on a ten-requests-a-day budget an eager
        // retry policy does not improve reliability, it removes the source. The
        // cache is the other half of that defence, and it is a backstop rather
        // than a fix — the real answer is the scheduled server-side job.
        self.transport = transport ?? CachingTransport(
            wrapping: RetryingTransport(wrapping: URLSessionTransport(), policy: .frugal),
            policy: .rateLimited
        )
        self.models = models
    }

    public func forecast(for spot: Spot) async throws -> [RawMarineSample] {
        let formatter = DateParsing.makeISO8601Formatter()
        return try await hours(for: spot).compactMap { sample(from: $0, formatter: formatter) }
    }

    public func ensemble(for spot: Spot) async throws -> [ModelSpread] {
        let formatter = DateParsing.makeISO8601Formatter()
        return try await hours(for: spot).compactMap { hour in
            guard let date = formatter.date(from: hour.time),
                  let heights = hour.waveHeight, heights.count > 1
            else { return nil }
            // Drop Stormglass's own blended "sg" value — including a derived
            // average alongside its inputs would understate the real spread.
            let independent = heights.filter { $0.key != "sg" }
            return ModelSpread(timestamp: date, waveHeightByModel: independent)
        }
    }

    // MARK: - Request

    private func hours(for spot: Spot) async throws -> [Hour] {
        var components = URLComponents(string: "https://api.stormglass.io/v2/weather/point")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(spot.latitude)),
            URLQueryItem(name: "lng", value: String(spot.longitude)),
            URLQueryItem(name: "params", value: [
                "waveHeight", "wavePeriod", "waveDirection",
                "swellHeight", "swellPeriod", "swellDirection",
                "windSpeed", "windDirection", "waterTemperature", "airTemperature"
            ].joined(separator: ",")),
            URLQueryItem(name: "source", value: (models + ["sg"]).joined(separator: ","))
        ]

        let data = try await transport.data(
            from: components.url!,
            headers: ["Authorization": apiKey]
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data).hours
        } catch {
            throw SourceError.malformedPayload("stormglass: \(error)")
        }
    }

    // MARK: - Decoding

    /// Every parameter arrives as `{"noaa": 1.2, "icon": 1.1, "sg": 1.15}`.
    private struct Hour: Decodable {
        let time: String
        let waveHeight: [String: Double]?
        let wavePeriod: [String: Double]?
        let waveDirection: [String: Double]?
        let swellHeight: [String: Double]?
        let swellPeriod: [String: Double]?
        let swellDirection: [String: Double]?
        let windSpeed: [String: Double]?
        let windDirection: [String: Double]?
        let waterTemperature: [String: Double]?
        let airTemperature: [String: Double]?
    }

    private struct Response: Decodable {
        let hours: [Hour]
    }

    private func sample(from hour: Hour, formatter: ISO8601DateFormatter) -> RawMarineSample? {
        guard let date = formatter.date(from: hour.time),
              let height = consensus(hour.waveHeight),
              let period = consensus(hour.wavePeriod),
              let direction = consensus(hour.waveDirection),
              let windSpeed = consensus(hour.windSpeed),
              let windDirection = consensus(hour.windDirection)
        else { return nil }

        var swell: SwellComponent?
        if let swellHeight = consensus(hour.swellHeight),
           let swellPeriod = consensus(hour.swellPeriod),
           let swellDirection = consensus(hour.swellDirection) {
            swell = SwellComponent(
                heightMeters: swellHeight,
                periodSeconds: swellPeriod,
                directionDegrees: swellDirection
            )
        }

        return RawMarineSample(
            timestamp: date,
            waveHeightMeters: height,
            wavePeriodSeconds: period,
            waveDirectionDegrees: direction,
            primarySwell: swell,
            windSpeedMPS: windSpeed,
            windDirectionDegrees: windDirection,
            airTemperatureC: consensus(hour.airTemperature),
            seaSurfaceTemperatureC: consensus(hour.waterTemperature)
        )
    }

    /// Prefer Stormglass's own blend where present, otherwise average the models
    /// we asked for. Directions are averaged naively, which is wrong across the
    /// 0/360 wrap — acceptable only because `sg` is nearly always present.
    private func consensus(_ values: [String: Double]?) -> Double? {
        guard let values, !values.isEmpty else { return nil }
        if let blended = values["sg"] { return blended }
        return values.values.reduce(0, +) / Double(values.count)
    }
}
