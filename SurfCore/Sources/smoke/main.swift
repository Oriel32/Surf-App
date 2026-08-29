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
//   swift run smoke [spot-id] [surfing|kitesurfing|wingFoil|sup] [beginner|intermediate|advanced]
//                    [--explain] [--today] [--at <yyyy-MM-ddTHH:mm, Israel time>]
//
// --explain prints every intermediate value of the wave transformation, which is
// what makes a disagreement with another forecast app diagnosable rather than
// just annoying.

let arguments = CommandLine.arguments
let explain = arguments.contains("--explain")
let todayTable = arguments.contains("--today")

/// `--at <when>` reports on a chosen hour instead of the current one.
///
/// Added because a field report is always about a time that has already passed.
/// On 2026-08-29 a surfer described a session between 09:30 and 10:20 at Bat Yam
/// and this tool could not be pointed at it: the only way to check the engine
/// against those hours was to have been running it during them. A verification
/// tool that can only verify the present cannot close the operating loop.
///
/// Accepts a bare local hour as well as a full stamp, in Israel time, because
/// nobody types a UTC offset from memory.
func parseWhen(_ raw: String) -> Date? {
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH",
        "yyyy-MM-dd"
    ]
    for format in formats {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        formatter.dateFormat = format
        if let date = formatter.date(from: raw) { return date }
    }
    return nil
}

// One pass, so that the value belonging to `--at` is never mistaken for a
// positional argument — it would otherwise be read as the spot id.
//
// Both results land in `let`s: a top-level `var` is main-actor isolated under
// Swift 6 and cannot then be read from the nonisolated `positional` below.
let (requestedHour, positionalArgs): (Date?, [String]) = {
    var when: Date?
    var positionals: [String] = []
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--at" {
            guard index + 1 < arguments.count else {
                FileHandle.standardError.write(Data("--at needs a time, e.g. --at 2026-08-29T10:00\n".utf8))
                exit(1)
            }
            let raw = arguments[index + 1]
            guard let parsed = parseWhen(raw) else {
                FileHandle.standardError.write(Data("--at: could not read '\(raw)' as a date\n".utf8))
                exit(1)
            }
            when = parsed
            index += 2
            continue
        }
        if !argument.hasPrefix("--") { positionals.append(argument) }
        index += 1
    }
    return (when, positionals)
}()

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

// The hour everything below reports on. `--at` selects a past or future hour;
// without it, now.
let now = requestedHour ?? Date()
let current = forecast.hours.min {
    abs($0.conditions.timestamp.timeIntervalSince(now)) < abs($1.conditions.timestamp.timeIntervalSince(now))
}!
let c = current.conditions

rule((requestedHour == nil ? "RIGHT NOW  (" : "REQUESTED HOUR  (") + clock(c.timestamp) + ")")
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
// The split behind that single height. Printed next to it because the combined
// number cannot say whether a rising sea is rising swell or rising chop, and
// that distinction is the entire 2026-08-29 Bat Yam finding.
if let swell = c.swellHeightMeters, let windSea = c.windSeaHeightMeters {
    print("  Swell / chop     : \(metres(swell)) swell + \(metres(windSea)) chop"
        + (c.windSeaEnergyShare.map { String(format: "   (chop = %.0f%% of the energy)", $0 * 100) } ?? ""))
}
if c.isCrossSea {
    print("  Cross sea        : swell and chop from opposite sides of the normal — confused water")
}
if let currentMPS = c.longshoreCurrentMPS, abs(currentMPS) >= 0.05 {
    let heading = currentMPS > 0 ? "toward \(Int(Compass.normalize(spot.shorelineNormalDegrees + 90)))°"
                                 : "toward \(Int(Compass.normalize(spot.shorelineNormalDegrees - 90)))°"
    print("  Longshore current: \(String(format: "%.2f m/s", abs(currentMPS))) \(heading)   [provisional]")
}
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
    print("  time   open-sea   beach     set ×\(String(format: "%.2f", WaveStatistics.oneInTen))  period   chop   wind             sea state  band")

    let calendar = Calendar.israelStandard
    for hour in forecast.hours where calendar.isDate(hour.conditions.timestamp, inSameDayAs: now) {
        let h = hour.conditions
        let set = SurfRange(significantMeters: h.waveHeightMeters).setMeters
        print("  " + pad(hhmm(h.timestamp), 7)
            + pad(metres(h.openSeaHeightMeters), 11)
            + pad(metres(h.waveHeightMeters), 10)
            + pad(metres(set), 10)
            + pad(seconds(h.periodSeconds), 9)
            + pad(h.windSeaEnergyShare.map { String(format: "%.0f%%", $0 * 100) } ?? "—", 7)
            + pad("\(knots(h.windSpeedKnots)) \(h.windRelation.rawValue)", 18)
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
    //
    // Taken from the outlook rather than re-derived here: computing it locally
    // took the max over all 24 hours while `peakScore` came from daylight only,
    // so this table printed a score from noon beside a wind reading from 03:00.
    let dayHours = forecast.hours.filter { calendar.isDate($0.conditions.timestamp, inSameDayAs: day.day) }
    guard let peak = day.peakHour else { continue }
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
    // The combined sea and the swell partition compared separately, because a
    // buoy disagreeing with the first while matching the second is a definition
    // mismatch and not a model error — which is exactly what happened here on
    // 2026-08-29 (combined +0.46 m, swell +0.02 m).
    if let modelSwell = c.openSeaSwellHeightMeters {
        let swellDelta = modelSwell - reading.significantWaveHeightMeters
        print("  model swell only  : \(metres(modelSwell))"
            + "   delta \(String(format: "%+.2f m", swellDelta))"
            + "  \(abs(swellDelta) < 0.3 ? "— swell channel agrees" : "— swell channel disagrees too")")
    }
    print("  period: model \(seconds(c.periodSeconds)) vs buoy \(seconds(reading.peakPeriodSeconds))"
        + "  \(String(format: "%+.1f s", c.periodSeconds - reading.peakPeriodSeconds))")

    // Keep the comparison instead of printing it and forgetting it. One run is
    // an anecdote; the series is what can actually tune a coefficient.
    //
    // Only when the model hour and the buoy reading are actually the same hour.
    // ISRAMAR serves one reading — the latest — so `--at` can pair a model value
    // from this morning against a measurement taken this afternoon. Printing
    // that comparison is fine and clearly labelled; *logging* it would put a
    // fabricated pair into the record that coefficients get tuned from, which is
    // the same class of mistake as the combined-versus-swell mismatch this log
    // was just taught to avoid.
    let hoursApart = abs(c.timestamp.timeIntervalSince(reading.observedAt)) / 3600

    // Anchored to the repository, not to wherever the process happens to be
    // standing. This was a real fork: running the tool from `SurfCore/` instead
    // of the repo root silently created a SECOND ledger at
    // `SurfCore/calibration/observations.jsonl`, so the history a coefficient
    // would eventually be tuned against depended on which directory somebody
    // typed the command in.
    //
    // `#filePath` is this source file at build time, four levels below the root:
    // SurfCore/Sources/smoke/main.swift.
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // smoke
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // SurfCore
        .deletingLastPathComponent()   // repo root
    let logURL = repoRoot
        .appendingPathComponent("calibration")
        .appendingPathComponent("observations.jsonl")
    guard hoursApart <= 1 else {
        print("  not logged: this model hour is "
            + String(format: "%.0f", hoursApart)
            + "h from the buoy reading")
        print("  (--at can outrun the buoy, which only ever serves its latest measurement)")
        print("\nSMOKE_OK")
        exit(0)
    }

    do {
        try CalibrationLog.append(
            CalibrationRecord(
                recordedAt: now,
                spotID: spot.id,
                stationID: reading.stationID,
                observedAt: reading.observedAt,
                modelOpenSeaHeightMeters: c.openSeaHeightMeters,
                modelPeriodSeconds: c.periodSeconds,
                modelSwellHeightMeters: c.openSeaSwellHeightMeters,
                modelSwellPeriodSeconds: c.openSeaSwellPeriodSeconds,
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
