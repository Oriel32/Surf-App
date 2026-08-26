import Foundation
import Observation
import SurfCore

/// Everything the user chose, remembered across launches.
///
/// Plain `UserDefaults` rather than `@AppStorage`, because `@AppStorage` is a
/// `DynamicProperty` that only works inside a `View` — an `@Observable` model
/// has to do its own persistence.
@MainActor
@Observable
final class SettingsStore {
    var sport: Sport { didSet { defaults.set(sport.rawValue, forKey: Key.sport) } }

    /// Not cosmetic: skill modulates both the Match Score and how aggressively
    /// safety alerts fire. Defaults to beginner and lets people opt upward,
    /// because the failure mode of over-warning is annoyance and the failure
    /// mode of under-warning is a rescue.
    var skill: SkillLevel { didSet { defaults.set(skill.rawValue, forKey: Key.skill) } }

    var heightUnit: HeightUnit { didSet { defaults.set(heightUnit.rawValue, forKey: Key.heightUnit) } }

    /// Ordered. The first favourite is the beach Home opens on.
    var favouriteSpotIDs: [String] { didSet { defaults.set(favouriteSpotIDs, forKey: Key.favourites) } }

    var showBuoy: Bool { didSet { defaults.set(showBuoy, forKey: Key.showBuoy) } }
    var showWebcams: Bool { didSet { defaults.set(showWebcams, forKey: Key.showWebcams) } }

    private let defaults: UserDefaults

    private enum Key {
        static let sport = "profile.sport"
        static let skill = "profile.skill"
        static let heightUnit = "display.heightUnit"
        static let favourites = "spots.favourites"
        static let showBuoy = "verify.buoy"
        static let showWebcams = "verify.webcams"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sport = defaults.string(forKey: Key.sport).flatMap(Sport.init(rawValue:)) ?? .surfing
        skill = defaults.string(forKey: Key.skill).flatMap(SkillLevel.init(rawValue:)) ?? .beginner
        heightUnit = defaults.string(forKey: Key.heightUnit)
            .flatMap(HeightUnit.init(rawValue:)) ?? .meters
        favouriteSpotIDs = defaults.stringArray(forKey: Key.favourites) ?? []
        showBuoy = defaults.object(forKey: Key.showBuoy) as? Bool ?? true
        showWebcams = defaults.object(forKey: Key.showWebcams) as? Bool ?? true
    }

    var profile: UserProfile {
        UserProfile(sport: sport, skill: skill)
    }

    func isFavourite(_ spotID: String) -> Bool {
        favouriteSpotIDs.contains(spotID)
    }

    func toggleFavourite(_ spotID: String) {
        if let index = favouriteSpotIDs.firstIndex(of: spotID) {
            favouriteSpotIDs.remove(at: index)
        } else {
            favouriteSpotIDs.append(spotID)
        }
    }

    /// The beach Home opens on: the first favourite, or nothing yet.
    var defaultSpotID: String? {
        favouriteSpotIDs.first
    }
}
