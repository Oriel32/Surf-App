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

let arguments = CommandLine.arguments
let spotID = arguments.count > 1 ? arguments[1] : "hadera"
let sport = Sport(rawValue: arguments.count > 2 ? arguments[2] : "surfing") ?? .surfing
let skill = SkillLevel(rawValue: arguments.count > 3 ? arguments[3] : "intermediate") ?? .intermediate
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

func rule(_ title: String) {
    print("\n\u{001B}[1m\(title)\u{001B}[0m")
    print(String(repeating: "─", count: max(title.count, 40)))
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
    print("\nThis is the failure the unit tests could not catch: the live payload")
    print("did not match the decoder. Check the URL and the Codable keys.")
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
print("  Open sea (model) : \(metres(c.openSeaHeightMeters))")
print("  At the beach     : \(metres(c.waveHeightMeters))   \(c.band.hebrew)  /  \(c.band.english)")
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

    print("  \(label) peak \(String(format: "%3d", day.peakScore))  \(String(format: "%-13@", window as NSString))"
        + " \(metres(p.waveHeightMeters))  \(seconds(p.periodSeconds))"
        + "  \(knots(p.windSpeedKnots)) \(p.windRelation.rawValue)  \(p.seaState.english)  \(p.band.english)"
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

case .stale(let reading, let age):
    print("  station \(reading.stationID): OFFLINE")
    print("  last reading \(metres(reading.significantWaveHeightMeters)) @ \(seconds(reading.peakPeriodSeconds)), \(describeAge(age))")
    print("  correctly withheld from display — this is the staleness gate working")

case .unavailable:
    print("  no buoy configured or reachable for this spot")
}

print("\nSMOKE_OK")
