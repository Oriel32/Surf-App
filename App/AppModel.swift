import Foundation
import Observation
import SurfCore

/// One model behind all five screens.
///
/// Forecasts are keyed by spot, so Home, Week, Spots and Detail read the same
/// cached state instead of each fetching its own copy. `ForecastRepository`
/// already coalesces concurrent requests per spot; keeping one model here means
/// they never have to.
@MainActor
@Observable
final class AppModel {
    let spots: [Spot]
    /// A `var` rather than a `let` so `$model.settings.sport` resolves to a
    /// writable binding; the instance itself never changes.
    var settings: SettingsStore

    /// Four states per spot, never a bare optional. "Nothing yet", "this is
    /// old" and "this is broken" are three different things to say to someone
    /// standing on the sand.
    private(set) var states: [String: DataState<SpotForecast>] = [:]

    var selectedSpotID: String

    private let repository: ForecastRepository

    init(repository: ForecastRepository, spots: [Spot], settings: SettingsStore) {
        self.repository = repository
        self.spots = spots
        self.settings = settings
        self.selectedSpotID = settings.defaultSpotID ?? spots.first?.id ?? ""
    }

    /// Open-Meteo for the forecast, ISRAMAR for ground truth.
    ///
    /// Stormglass is deliberately absent. Its free tier is roughly ten requests
    /// a day, which cannot be called from a device at all, so model confidence
    /// stays absent rather than invented.
    static func live() -> AppModel {
        AppModel(
            repository: ForecastRepository(
                primary: OpenMeteoClient(),
                observations: IsramarClient()
            ),
            spots: (try? SpotCatalog.load()) ?? [],
            settings: SettingsStore()
        )
    }

    // MARK: - Lookup

    var selectedSpot: Spot? {
        spot(id: selectedSpotID)
    }

    func spot(id: String) -> Spot? {
        spots.first { $0.id == id }
    }

    func state(for spotID: String) -> DataState<SpotForecast> {
        states[spotID] ?? .loading
    }

    var selectedState: DataState<SpotForecast> {
        state(for: selectedSpotID)
    }

    /// Changing beach, sport or skill asks a different question, so the screen
    /// refetches rather than relabelling stale numbers.
    var reloadKey: String {
        "\(selectedSpotID)|\(settings.sport.rawValue)|\(settings.skill.rawValue)"
    }

    var profileKey: String {
        "\(settings.sport.rawValue)|\(settings.skill.rawValue)"
    }

    // MARK: - Loading

    func loadSelected() async {
        guard let spot = selectedSpot else { return }
        await load(spot)
    }

    func load(_ spot: Spot) async {
        // Only fall back to a spinner when there is genuinely nothing to show.
        // Blanking a good forecast in order to redraw it makes a refresh feel
        // broken.
        if states[spot.id]?.value == nil {
            states[spot.id] = .loading
        }
        states[spot.id] = await repository.forecastState(for: spot, profile: settings.profile)
    }

    /// Every spot at once, for the Spots tab.
    ///
    /// Concurrent rather than sequential: eleven serial round trips is a
    /// visibly dead screen. Results land as they arrive, so the list fills in
    /// progressively instead of waiting for the slowest beach.
    func loadAll() async {
        await withTaskGroup(of: (String, DataState<SpotForecast>).self) { group in
            for spot in spots {
                if states[spot.id]?.value == nil {
                    states[spot.id] = .loading
                }
                group.addTask { [repository, profile = settings.profile] in
                    (spot.id, await repository.forecastState(for: spot, profile: profile))
                }
            }
            for await (id, state) in group {
                states[id] = state
            }
        }
    }

    func refreshSelected() async {
        // The last known good forecast is deliberately kept: a pull-to-refresh
        // on a dead connection must not turn a working screen into an error.
        await repository.invalidate()
        await loadSelected()
    }

    func refreshAll() async {
        await repository.invalidate()
        await loadAll()
    }

    // MARK: - Derived

    /// The hour the user is standing in.
    func currentHour(for spotID: String) -> HourlyForecast? {
        guard let forecast = state(for: spotID).value else { return nil }
        let now = Date()
        return forecast.hours.last { $0.conditions.timestamp <= now } ?? forecast.hours.first
    }

    var currentHour: HourlyForecast? {
        currentHour(for: selectedSpotID)
    }

    /// Today's hours in local beach time — a 05:00 dawn session belongs to the
    /// day the surfer thinks it does.
    func hours(for spotID: String, on day: Date) -> [HourlyForecast] {
        guard let forecast = state(for: spotID).value else { return [] }
        let calendar = Calendar.israelStandard
        return forecast.hours
            .filter { calendar.isDate($0.conditions.timestamp, inSameDayAs: day) }
            .sorted { $0.conditions.timestamp < $1.conditions.timestamp }
    }

    var today: [HourlyForecast] {
        hours(for: selectedSpotID, on: Date())
    }

    /// Per-day best windows. Never a daily mean: a day that is glassy at dawn
    /// and blown out by noon averages to a number that is wrong at every hour
    /// it claims to describe.
    ///
    /// Each `DayOutlook` carries the hour its score came from, so the Week row
    /// draws its height, slang and wind from that same hour rather than picking
    /// its own maximum and describing a different one.
    func days(for spotID: String) -> [DayOutlook] {
        guard let forecast = state(for: spotID).value else { return [] }
        return WindowFinder.dailyWindows(in: forecast.hours)
    }

    /// Spots ranked for the Spots tab: best score first, unscored last.
    ///
    /// On a marginal day the useful answer is often "not your usual beach, but
    /// Palmachim is working", and ranking is what surfaces that.
    var rankedSpots: [Spot] {
        spots.sorted { left, right in
            let leftScore = currentHour(for: left.id)?.score.value ?? -1
            let rightScore = currentHour(for: right.id)?.score.value ?? -1
            if leftScore != rightScore { return leftScore > rightScore }
            return left.nameHebrew < right.nameHebrew
        }
    }

    var favouriteSpots: [Spot] {
        settings.favouriteSpotIDs.compactMap { spot(id: $0) }
    }
}
