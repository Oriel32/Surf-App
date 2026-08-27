import Foundation

/// The forecast spine.
///
/// Chosen over a generic weather API because it reports **swell separately from
/// wind waves**. That distinction is the whole product: a 0.7 m groundswell at
/// 9 s is a good session and a 0.7 m wind chop at 4 s is unsurfable, and an API
/// that reports only a combined significant height cannot tell them apart.
///
/// Marine and atmospheric variables live on two different hosts, so this issues
/// two requests concurrently and zips them by timestamp.
public struct OpenMeteoClient: ForecastSource {
    public let identifier = "open-meteo"

    private let transport: any HTTPTransport
    private let model: String

    /// - Parameter model: `best_match` blends the highest-resolution model
    ///   available at each step, which is the only option that satisfies both
    ///   halves of this app.
    ///
    ///   Measured against the Israeli coast for a 7-day request:
    ///   `ewam` (DWD, 5 km) returns 168 timestamps but **77 of them null** — it
    ///   is a short-range regional model and runs out after roughly 3.8 days,
    ///   which cannot fill the Week screen. `gwam` (25 km) and `ecmwf_wam025`
    ///   return a full 168 but at far coarser resolution. `best_match` gets
    ///   EWAM's resolution near-term and full coverage to day 7.
    ///
    ///   Note that `meteofrance_wam` is **not** a valid Open-Meteo model id —
    ///   the API rejects it outright.
    public init(transport: (any HTTPTransport)? = nil, model: String = "best_match") {
        // Cache outermost, retry inside it: a repeat request costs nothing at
        // all, and a request that needed three attempts is stored once under the
        // URL that finally answered. Retrying is not optional here either, since
        // this is the one source the screen cannot do without and a single
        // dropped connection must not empty the app.
        self.transport = transport ?? CachingTransport(
            wrapping: RetryingTransport(wrapping: URLSessionTransport()),
            policy: .modelRun
        )
        self.model = model
    }

    public func forecast(for spot: Spot) async throws -> [RawMarineSample] {
        switch spot.basin {
        case .mediterranean:
            return try await marineForecast(for: spot)
        case .gulfOfEilat:
            return try await windOnlyForecast(for: spot)
        }
    }

    private func marineForecast(for spot: Spot) async throws -> [RawMarineSample] {
        // Two independent calls of different types — the textbook `async let`
        // case. Both are cancelled automatically if either throws.
        async let marineData = transport.data(from: marineURL(for: spot), headers: [:])
        async let weatherData = transport.data(from: weatherURL(for: spot), headers: [:])

        let marine = try await decode(MarineResponse.self, from: marineData)
        let weather = try await decode(WeatherResponse.self, from: weatherData)

        return try merge(marine: marine, weather: weather)
    }

    /// The Gulf of Eilat is outside the marine model domain entirely — the
    /// marine endpoint answers **HTTP 400** for these coordinates, not an empty
    /// series. Asking it anyway would fail the whole fetch and leave Eilat with
    /// no forecast at all.
    ///
    /// Nothing is lost by not asking: `WaveTransform` discards model wave values
    /// in this basin regardless and synthesises height and period from the local
    /// wind, because the gulf sees wind chop and no swell. So only the
    /// atmospheric endpoint (global coverage) is called, and the wave fields are
    /// left at zero for the transform to fill in.
    private func windOnlyForecast(for spot: Spot) async throws -> [RawMarineSample] {
        let data = try await transport.data(from: weatherURL(for: spot), headers: [:])
        let weather = try decode(WeatherResponse.self, from: data)
        let formatter = DateParsing.makeUTCFormatter(DateParsing.openMeteoFormat)
        let daylight = DaylightTable(weather.daily, formatter: formatter)

        return weather.hourly.time.enumerated().compactMap { index, stamp in
            guard let date = formatter.date(from: stamp),
                  let speed = weather.hourly.windSpeed?[safe: index] ?? nil,
                  let direction = weather.hourly.windDirection?[safe: index] ?? nil
            else { return nil }

            return RawMarineSample(
                timestamp: date,
                waveHeightMeters: 0,
                wavePeriodSeconds: 0,
                waveDirectionDegrees: direction,
                windSpeedMPS: speed,
                windDirectionDegrees: direction,
                windGustMPS: weather.hourly.windGusts?[safe: index] ?? nil,
                airTemperatureC: weather.hourly.temperature?[safe: index] ?? nil,
                isDaylight: daylight.isDaylight(date, dayKey: String(stamp.prefix(10)))
            )
        }
    }

    // MARK: - URLs

    private func marineURL(for spot: Spot) -> URL {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(spot.latitude)),
            URLQueryItem(name: "longitude", value: String(spot.longitude)),
            URLQueryItem(name: "hourly", value: [
                "wave_height", "wave_period", "wave_direction",
                "swell_wave_height", "swell_wave_period", "swell_wave_peak_period",
                "swell_wave_direction",
                "wind_wave_height", "wind_wave_period", "wind_wave_peak_period",
                "wind_wave_direction",
                "sea_surface_temperature", "sea_level_height_msl"
            ].joined(separator: ",")),
            URLQueryItem(name: "models", value: model),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]
        return components.url!
    }

    private func weatherURL(for spot: Spot) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(spot.latitude)),
            URLQueryItem(name: "longitude", value: String(spot.longitude)),
            URLQueryItem(
                name: "hourly",
                value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m"
            ),
            // Sunrise and sunset ride along on the request we were making
            // anyway, which is what makes daylight filtering free. Asking a
            // separate endpoint for them would have cost a round trip per spot.
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            // Ask for SI at the boundary so nothing downstream has to convert.
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]
        return components.url!
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SourceError.malformedPayload("open-meteo: \(error)")
        }
    }

    /// Open-Meteo is columnar: parallel arrays keyed by variable name, with
    /// `null` wherever a value is missing.
    private struct MarineResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let waveHeight: [Double?]?
            let wavePeriod: [Double?]?
            let waveDirection: [Double?]?
            let swellWaveHeight: [Double?]?
            let swellWavePeriod: [Double?]?
            let swellWavePeakPeriod: [Double?]?
            let swellWaveDirection: [Double?]?
            let windWaveHeight: [Double?]?
            let windWavePeriod: [Double?]?
            let windWavePeakPeriod: [Double?]?
            let windWaveDirection: [Double?]?
            let seaSurfaceTemperature: [Double?]?
            let seaLevelHeightMsl: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case waveHeight = "wave_height"
                case wavePeriod = "wave_period"
                case waveDirection = "wave_direction"
                case swellWaveHeight = "swell_wave_height"
                case swellWavePeriod = "swell_wave_period"
                case swellWavePeakPeriod = "swell_wave_peak_period"
                case swellWaveDirection = "swell_wave_direction"
                case windWaveHeight = "wind_wave_height"
                case windWavePeriod = "wind_wave_period"
                case windWavePeakPeriod = "wind_wave_peak_period"
                case windWaveDirection = "wind_wave_direction"
                case seaSurfaceTemperature = "sea_surface_temperature"
                case seaLevelHeightMsl = "sea_level_height_msl"
            }
        }
        let hourly: Hourly
    }

    private struct WeatherResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let windSpeed: [Double?]?
            let windDirection: [Double?]?
            let windGusts: [Double?]?
            let temperature: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case windSpeed = "wind_speed_10m"
                case windDirection = "wind_direction_10m"
                case windGusts = "wind_gusts_10m"
                case temperature = "temperature_2m"
            }
        }

        /// One entry per forecast day, in the same `yyyy-MM-dd` keying as the
        /// hourly timestamps' date prefix.
        struct Daily: Decodable {
            let time: [String]
            let sunrise: [String?]?
            let sunset: [String?]?
        }

        let hourly: Hourly
        /// Optional so a response without `daily` still decodes — daylight then
        /// degrades to "always", which is the pre-existing behaviour.
        let daily: Daily?
    }

    /// Sunrise and sunset per calendar day, for deciding whether an hour is
    /// surfable at all.
    private struct DaylightTable {
        private let byDay: [String: (rise: Date, set: Date)]

        init(_ daily: WeatherResponse.Daily?, formatter: DateFormatter) {
            guard let daily else { byDay = [:]; return }
            var table: [String: (Date, Date)] = [:]
            for (index, day) in daily.time.enumerated() {
                guard let riseText = daily.sunrise?[safe: index] ?? nil,
                      let setText = daily.sunset?[safe: index] ?? nil,
                      let rise = formatter.date(from: riseText),
                      let set = formatter.date(from: setText)
                else { continue }
                table[day] = (rise, set)
            }
            byDay = table
        }

        /// Permissive when the day is missing: an absent sunrise must not make
        /// a whole day vanish from the forecast.
        func isDaylight(_ stamp: Date, dayKey: String) -> Bool {
            guard let window = byDay[dayKey] else { return true }
            return stamp >= window.rise && stamp <= window.set
        }
    }

    // MARK: - Merge

    private func merge(marine: MarineResponse, weather: WeatherResponse) throws -> [RawMarineSample] {
        // Index the wind series by timestamp rather than assuming the two
        // endpoints return identical, aligned time arrays.
        var windByTime: [String: (speed: Double, direction: Double, gust: Double?, air: Double?)] = [:]
        for (index, stamp) in weather.hourly.time.enumerated() {
            guard let speed = weather.hourly.windSpeed?[safe: index] ?? nil,
                  let direction = weather.hourly.windDirection?[safe: index] ?? nil
            else { continue }
            windByTime[stamp] = (
                speed,
                direction,
                weather.hourly.windGusts?[safe: index] ?? nil,
                weather.hourly.temperature?[safe: index] ?? nil
            )
        }

        // One formatter for the whole series — building one per row would cost
        // more than the rest of the parse put together.
        let formatter = DateParsing.makeUTCFormatter(DateParsing.openMeteoFormat)
        let daylight = DaylightTable(weather.daily, formatter: formatter)

        let hourly = marine.hourly
        return hourly.time.enumerated().compactMap { index, stamp -> RawMarineSample? in
            guard let date = formatter.date(from: stamp),
                  let height = hourly.waveHeight?[safe: index] ?? nil,
                  let period = hourly.wavePeriod?[safe: index] ?? nil,
                  let direction = hourly.waveDirection?[safe: index] ?? nil,
                  let wind = windByTime[stamp]
            else { return nil }

            return RawMarineSample(
                timestamp: date,
                waveHeightMeters: height,
                wavePeriodSeconds: period,
                waveDirectionDegrees: direction,
                primarySwell: component(
                    hourly.swellWaveHeight?[safe: index] ?? nil,
                    hourly.swellWavePeriod?[safe: index] ?? nil,
                    hourly.swellWavePeakPeriod?[safe: index] ?? nil,
                    hourly.swellWaveDirection?[safe: index] ?? nil
                ),
                windWave: component(
                    hourly.windWaveHeight?[safe: index] ?? nil,
                    hourly.windWavePeriod?[safe: index] ?? nil,
                    hourly.windWavePeakPeriod?[safe: index] ?? nil,
                    hourly.windWaveDirection?[safe: index] ?? nil
                ),
                windSpeedMPS: wind.speed,
                windDirectionDegrees: wind.direction,
                windGustMPS: wind.gust,
                airTemperatureC: wind.air,
                seaSurfaceTemperatureC: hourly.seaSurfaceTemperature?[safe: index] ?? nil,
                seaLevelMeters: hourly.seaLevelHeightMsl?[safe: index] ?? nil,
                isDaylight: daylight.isDaylight(date, dayKey: String(stamp.prefix(10)))
            )
        }
    }

    /// - Parameter peak: Tp. Absent on some model runs, in which case the train
    ///   falls back to the mean period rather than being dropped.
    private func component(
        _ height: Double?,
        _ period: Double?,
        _ peak: Double?,
        _ direction: Double?
    ) -> SwellComponent? {
        guard let height, let period, let direction else { return nil }
        return SwellComponent(
            heightMeters: height,
            periodSeconds: period,
            peakPeriodSeconds: peak,
            directionDegrees: direction
        )
    }
}

extension Array {
    /// Columnar payloads routinely disagree about series length; indexing one
    /// against another's count is a crash waiting for a bad model run.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
