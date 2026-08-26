import Foundation
import Observation
import SurfCore

/// The screen's state, decoupled from the fetching underneath it.
///
/// `SurfCore` is a nonisolated library and this is the layer that decides to
/// bring its results back to the main actor. Dependencies arrive through the
/// initialiser, so a preview or a test can hand it a canned repository.
@MainActor
@Observable
final class ForecastViewModel {
    /// Four states, never a bare optional. "Nothing yet", "this is old" and
    /// "this is broken" are three different things to say to someone standing
    /// on the sand, and a `SpotForecast?` can only say one of them.
    private(set) var state: DataState<SpotForecast> = .loading

    let spots: [Spot]
    var selectedSpotID: String
    var profile: UserProfile

    private let repository: ForecastRepository

    init(
        repository: ForecastRepository,
        spots: [Spot],
        profile: UserProfile = UserProfile()
    ) {
        self.repository = repository
        self.spots = spots
        self.selectedSpotID = spots.first?.id ?? ""
        self.profile = profile
    }

    /// The real thing: Open-Meteo for the forecast, ISRAMAR for ground truth.
    ///
    /// Stormglass is deliberately absent. Its free tier is roughly ten requests
    /// a day, which cannot be called from a device at all, so model confidence
    /// stays `nil` until a scheduled server-side job exists. An invented
    /// confidence figure would be worse than none.
    static func live() -> ForecastViewModel {
        ForecastViewModel(
            repository: ForecastRepository(
                primary: OpenMeteoClient(),
                observations: IsramarClient()
            ),
            spots: (try? SpotCatalog.load()) ?? []
        )
    }

    var selectedSpot: Spot? {
        spots.first { $0.id == selectedSpotID }
    }

    /// Changing the beach or the sport asks a different question, so the screen
    /// refetches. Skill level changes the safety thresholds, so it counts too.
    var reloadKey: String {
        "\(selectedSpotID)|\(profile.sport.rawValue)|\(profile.skill.rawValue)"
    }

    func load() async {
        guard let spot = selectedSpot else {
            state = .failed(reason: "spot catalogue is empty")
            return
        }
        // Only fall back to a spinner when there is genuinely nothing to show.
        // Blanking a good forecast to redraw it is how a refresh feels broken.
        if state.value == nil {
            state = .loading
        }
        state = await repository.forecastState(for: spot, profile: profile)
    }

    func refresh() async {
        // The last known good forecast is deliberately kept: a pull-to-refresh
        // on a dead connection must not turn a working screen into an error.
        await repository.invalidate()
        await load()
    }

    /// The hour the user is standing in.
    var currentHour: HourlyForecast? {
        guard let forecast = state.value else { return nil }
        let now = Date()
        return forecast.hours.last { $0.conditions.timestamp <= now }
            ?? forecast.hours.first
    }

    /// Today's remaining hours, in local beach time — a 05:00 dawn session
    /// belongs to the day the surfer thinks it does.
    var today: [HourlyForecast] {
        guard let forecast = state.value else { return [] }
        let calendar = Calendar.israelStandard
        let now = Date()
        return forecast.hours.filter {
            calendar.isDate($0.conditions.timestamp, inSameDayAs: now)
        }
    }
}
