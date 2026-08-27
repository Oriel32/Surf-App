import Foundation
import SurfCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Live smoke test: hits the real Open-Meteo and ISRAMAR endpoints, runs the full
// pipeline, and puts the model's answer next to a real buoy measurement.
//
// The unit suite proves the logic is self-consistent. This proves the decoders
// match what the providers actually send, which no fixture can.
//
//   swift run smoke [spot-id] [surfing|kitesurfing|wingFoil|sup] [beginner|intermediate|advanced] [--explain]
//
// --explain prints every intermediate value of the wave transformation, which is
// what makes a disagreement with another forecast app diagnosable rather than
// just annoying.

let arguments = CommandLine.arguments
let explain = arguments.contains("--explain")
let todayTable = arguments.contains("--today")
let positionalArgs = Array(arguments.dropFirst().filter { !$0.hasPrefix("--") })

func positional(_ index: Int, default fallback: String) -> String {
    index < positionalArgs.count ? positionalArgs[index] : fallback
}

let spotID = positional(0, default: "hadera")
let sport = Sport(rawValue: positional(1, default: "surfing")) ?? .surfing
let skill = SkillLevel(rawValue: positional(2, default: "intermediate")) ?? .intermediate
let profile = UserProfile(sport: sport, skill: skill)

// MARK: - Formatting

let israel = TimeZone(identifier: "Asia/Jerusalem") ?? .current

func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = israel
    return formatter.string(from: date)
}

func hhmm(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = israel
    return formatter.string(from: date)
}

func metres(_ value: Double) -> String { String(format: "%.2f m", value) }
func seconds(_ value: Double) -> String { String(format: "%.1f s", value) }
func knots(_ value: Double) -> String { String(format: "%.0f kt", value) }
func kmh(_ knotsValue: Double) -> String { String(format: "%.0f km/h", knotsValue * 1.852) }

// Foundation on Linux ignores the width in `%-10@`, so padding is done here
// rather than in a format string.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
}

func rule(_ title: String) {
    print("\n\u{001B}[1m\(title)\u{001B}[0m")
    print(String(repeating: "─", count: max(title.count, 40)))
}

enum FailureKind {
    case network
    case rejected(Int)
    case schema
}

func diagnose(_ error: any Error) -> FailureKind {
    if let source = error as? SourceError {
        switch source {
        case .transport: return .network
        case .badStatus(let code): return .rejected(code)
        case .malformedPayload, .unknownStation, .staleObservation: return .schema
        }
    }
    if error is URLError { return .network }
    // Off-Apple, URLSession failures surface as NSError in this domain rather
    // than bridging to URLError.
    if (error as NSError).domain == NSURLErrorDomain { return .network }
    return .schema
}

func describeAge(_ interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    if minutes < 90 { return "\(minutes) minutes ago" }
    let hours = minutes / 60
    if hours < 48 { return "\(hours) hours ago" }
    return "\(hours / 24) days ago"
}

// MARK: - Run

print("SurfCore live smoke test — \(clock(Date())) Israel time")

let spots: [Spot]
do {
    spots = try SpotCatalog.load()
} catch {
    print("FAIL: could not load the spot catalogue: \(error)")
    exit(1)
}

guard let spot = spots.first(where: { $0.id == spotID }) else {
    print("FAIL: unknown spot '\(spotID)'. Known ids:")
    for candidate in spots { print("  \(candidate.id)  — \(candidate.nameEnglish)") }
    exit(1)
}

rule("SPOT")
print("  \(spot.nameEnglish)  (\(spot.nameHebrew))")
print("  \(spot.latitude), \(spot.longitude)   basin: \(spot.basin.rawValue)")
print("  exposure \(spot.exposureCoefficient) · faces \(Int(spot.shorelineNormalDegrees))° · break depth \(spot.breakDepthMeters) m")
print("  profile: \(sport.rawValue) / \(skill.rawValue)")

let repository = ForecastRepository(
    primary: OpenMeteoClient(),
    observations: IsramarClient()
)

let forecast: SpotForecast
do {
    rule("FETCHING")
    print("  Open-Meteo marine + forecast …")
    forecast = try await repository.forecast(for: spot, profile: profile)
    print("  OK — \(forecast.hours.count) hourly samples decoded")
} catch {
    print("  FAIL: \(error)")
    // Naming the wrong cause sends the reader to the wrong file. A dropped
    // connection and a schema change look nothing alike and are fixed in
    // completely different places, so say which one this was.
    switch diagnose(error) {
    case .network:
        print("\nThe request never completed — this is a transport failure, not a")
        print("schema change. The retry policy already tried and gave up, so check")
        print("the connection before touching any decoder.")
    case .rejected(let code):
        print("\nThe server answered \(code). The request reached it and was refused,")
        print("so check the URL, the parameters and the key — not the connection.")
    case .schema:
        print("\nThis is the failure the unit tests could not catch: the live payload")
        print("did not match the decoder. Check the URL and the Codable keys.")
    }
    exit(1)
}

guard !forecast.hours.isEmpty else {
    print("FAIL: decoded zero hours — the response parsed but yielded nothing.")
    exit(1)
}

// MARK: - Now

let now = Date()
let current = forecast.hours.min {
    abs($0.conditions.timestamp.timeIntervalSince(now)) < abs($1.conditions.timestamp.timeIntervalSince(now))
}!
let c = current.conditions

rule("RIGHT NOW  (\(clock(c.timestamp)))")
// What the user actually reads, straight from the translation layer rather than
// re-formatted here. Printing a raw metre value instead was hiding the fact that
// the product already quotes a range.
print("  AS SHOWN         : \(Translator.present(current).waveLine)")
print("  Open sea (model) : \(metres(c.openSeaHeightMeters))")
print("  At the beach     : \(metres(c.waveHeightMeters))   \(c.band.hebrew)  /  \(c.band.english)")
if c.isDepthLimited {
    print("  Depth-limited    : bar holds \(metres(c.breakingLimitMeters)); score sees \(metres(c.rideableHeightMeters))")
}
print("  Period           : \(seconds(c.periodSeconds))")
print("  Sea state        : \(c.seaState.hebrew)  /  \(c.seaState.english)")
print("  Wind             : \(knots(c.windSpeedKnots)) \(c.windRelation.rawValue) (from \(Int(c.windDirectionDegrees))°)")
if let water = c.seaSurfaceTemperatureC { print("  Water            : \(String(format: "%.1f °C", water))") }
if let air = c.airTemperatureC { print("  Air              : \(String(format: "%.1f °C", air))") }
if c.isSynthetic {
    print("  NOTE             : locally derived from wind, not modelled (Gulf of Eilat)")
} else if c.openSeaHeightMeters > 0.01 {
    print("  Transform factor : ×\(String(format: "%.2f", c.waveHeightMeters / c.openSeaHeightMeters))")
}

// MARK: - Explain

if explain {
    rule("TRANSFORMATION — every step  (\(clock(c.timestamp)))")

    // The repository hands back transformed conditions and keeps no raw sample,
    // so the raw hour is refetched here rather than widening SpotForecast for a
    // diagnostic. The height printed below is then checked against the one the
    // repository produced — if the two disagree, this trace is describing a
    // different computation than the one that ships, and is worthless.
    do {
        let samples = try await OpenMeteoClient().forecast(for: spot)
        guard let raw = samples.min(by: {
            abs($0.timestamp.timeIntervalSince(c.timestamp)) < abs($1.timestamp.timeIntervalSince(c.timestamp))
        }) else {
            print("  no raw sample to explain")
            exit(1)
        }

        print("  OPEN SEA (model) \(metres(raw.waveHeightMeters))"
            + "  \(seconds(raw.wavePeriodSeconds))  from \(Int(raw.waveDirectionDegrees))°")
        print("  spot faces \(Int(spot.shorelineNormalDegrees))° · exposure \(spot.exposureCoefficient)")
        print("")

        let (replayed, trace) = WaveTransform.explain(raw, at: spot)
        for line in trace.report() { print("  \(line)") }

        if let net = trace.netFactor(openSeaHeightMeters: raw.waveHeightMeters) {
            print("  NET        ×\(String(format: "%.3f", net)) on the open-sea height")
        }

        if abs(replayed.waveHeightMeters - c.waveHeightMeters) > 0.005 {
            print("\n  ⚠ TRACE DISAGREES WITH THE PIPELINE:"
                + " trace \(metres(replayed.waveHeightMeters))"
                + " vs forecast \(metres(c.waveHeightMeters)).")
            print("    Most likely the refetched hour is a different model run, not a bug in")
            print("    the trace — rerun and check the timestamps before trusting either.")
        }
    } catch {
        print("  could not refetch the raw hour to explain it: \(error)")
    }
}

rule("MATCH SCORE")
print("  \(current.score.value)/100  for \(current.score.sport.rawValue)")
for (key, value) in current.score.components.sorted(by: { $0.key < $1.key }) {
    let bar = String(repeating: "█", count: Int((value * 20).rounded()))
    print(String(format: "    %-10@ %.2f  %@", key as NSString, value, bar as NSString))
}

rule("SAFETY")
if current.alerts.isEmpty {
    print("  no alerts")
} else {
    for alert in current.alerts {
        print("  [\(alert.severity.rawValue.uppercased())] \(alert.hebrewTitle)")
        print("      \(alert.hebrewBody)")
    }
}

rule("BEST WINDOW TODAY")
if let window = forecast.bestWindowToday {
    print("  \(hhmm(window.start))–\(hhmm(window.end))   peak \(window.peakScore)/100")
} else {
    print("  nothing today clears the bar — don't bother driving out")
}

// MARK: - Today, hour by hour

// Every other forecast app publishes a three-hourly table for today. Ours was
// only ever printable one hour at a time, which made "your numbers disagree with
// theirs" impossible to check systematically. This prints the same shape of
// table so the two can be read side by side.
if todayTable {
    rule("TODAY, HOUR BY HOUR")
    print("  time   open-sea   beach     set ×\(String(format: "%.2f", WaveStatistics.oneInTen))  period   wind              sea state  band")

    let calendar = Calendar.israelStandard
    for hour in forecast.hours where calendar.isDate(hour.conditions.timestamp, inSameDayAs: now) {
        let h = hour.conditions
        let set = SurfRange(significantMeters: h.waveHeightMeters).setMeters
        print("  " + pad(hhmm(h.timestamp), 7)
            + pad(metres(h.openSeaHeightMeters), 11)
            + pad(metres(h.waveHeightMeters), 10)
            + pad(metres(set), 10)
            + pad(seconds(h.periodSeconds), 9)
            + pad("\(kmh(h.windSpeedKnots)) \(h.windRelation.rawValue)", 18)
            + pad(h.seaState.english, 11)
            + h.band.english)
    }
}

rule("NEXT 7 DAYS")
let calendar = Calendar.israelStandard
for day in WindowFinder.dailyWindows(in: forecast.hours) {
    let label = String(clock(day.day).prefix(10))
    let window = day.window.map { "\(hhmm($0.start))–\(hhmm($0.end))" } ?? "—"

    // Report the conditions at the day's best hour, since that is what the Week
    // row actually promises. A daily mean would describe no hour at all.
    let dayHours = forecast.hours.filter { calendar.isDate($0.conditions.timestamp, inSameDayAs: day.day) }
    guard let peak = dayHours.max(by: { $0.score.value < $1.score.value }) else { continue }
    let p = peak.conditions

    // The day's biggest hour, separately from its best-scoring hour. Another
    // app's week graph plots the day's maximum, and comparing that against our
    // best-*scoring* hour compares two different questions. Carrying the
    // open-sea maximum beside it is what separates "our model input differs
    // from theirs" from "our transform is wrong" — the two need opposite fixes.
    let maxBeach = dayHours.map(\.conditions.waveHeightMeters).max() ?? 0
    let maxOpenSea = dayHours.map(\.conditions.openSeaHeightMeters).max() ?? 0

    print("  \(label) peak \(String(format: "%3d", day.peakScore))  \(pad(window, 13))"
        + " \(metres(p.waveHeightMeters))  \(seconds(p.periodSeconds))"
        + "  \(pad("\(knots(p.windSpeedKnots)) \(p.windRelation.rawValue)", 18))\(pad(p.seaState.english, 8))\(pad(p.band.english, 16))"
        + "max \(metres(maxOpenSea))→\(metres(maxBeach))"
        + (peak.alerts.isEmpty ? "" : "  ALERT:\(peak.alerts.map(\.severity.rawValue).joined(separator: ","))"))
}

// MARK: - Ground truth

rule("GROUND TRUTH — ISRAMAR buoy")
switch forecast.buoy {
case .fresh(let reading):
    print("  station \(reading.stationID): \(metres(reading.significantWaveHeightMeters)) @ \(seconds(reading.peakPeriodSeconds))")
    print("  measured \(describeAge(reading.age(asOf: now)))  [FRESH]")

    // The reality check the whole product rests on. The buoy sits offshore, so
    // compare it against the model's OPEN-SEA figure, not the transformed
    // beach height — comparing to the beach value would flatter the model.
    let delta = c.openSeaHeightMeters - reading.significantWaveHeightMeters
    print("  model open-sea same hour: \(metres(c.openSeaHeightMeters))")
    print("  delta: \(String(format: "%+.2f m", delta))  \(abs(delta) < 0.3 ? "— models agree with reality" : "— MODEL AND BUOY DISAGREE")")
    print("  period: model \(seconds(c.periodSeconds)) vs buoy \(seconds(reading.peakPeriodSeconds))"
        + "  \(String(format: "%+.1f s", c.periodSeconds - reading.peakPeriodSeconds))")

    // Keep the comparison instead of printing it and forgetting it. One run is
    // an anecdote; the series is what can actually tune a coefficient.
    let logURL = URL(fileURLWithPath: "calibration/observations.jsonl")
    do {
        try CalibrationLog.append(
            CalibrationRecord(
                recordedAt: now,
                spotID: spot.id,
                stationID: reading.stationID,
                observedAt: reading.observedAt,
                modelOpenSeaHeightMeters: c.openSeaHeightMeters,
                modelPeriodSeconds: c.periodSeconds,
                buoyHeightMeters: reading.significantWaveHeightMeters,
                buoyPeakPeriodSeconds: reading.peakPeriodSeconds
            ),
            to: logURL
        )
        let history = try CalibrationLog.read(from: logURL)
        let summary = CalibrationLog.summarise(history, spotID: spot.id)
        print("  logged. \(summary.count) observation(s) for this spot so far")
        if summary.count >= 2 {
            print("    height bias \(String(format: "%+.2f m", summary.heightBiasMeters))"
                + "  RMSE \(String(format: "%.2f m", summary.heightRMSEMeters)))")
            print("    period bias \(String(format: "%+.1f s", summary.periodBiasSeconds))"
                + "  RMSE \(String(format: "%.1f s", summary.periodRMSESeconds)))")
        }
        if summary.count < 30 {
            print("    (need 30+ before the bias is worth tuning against)")
        }
    } catch {
        // A logging failure must never fail the smoke run — the point of the
        // run is the forecast, not the bookkeeping.
        print("  (could not write calibration log: \(error))")
    }

case .stale(let reading, let age):
    print("  station \(reading.stationID): OFFLINE")
    print("  last reading \(metres(reading.significantWaveHeightMeters)) @ \(seconds(reading.peakPeriodSeconds)), \(describeAge(age))")
    print("  correctly withheld from display — this is the staleness gate working")

case .unavailable:
    print("  no buoy configured or reachable for this spot")
}

print("\nSMOKE_OK")
