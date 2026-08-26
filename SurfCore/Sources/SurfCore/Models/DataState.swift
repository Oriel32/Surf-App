import Foundation

/// The four states every screen in this app has to design for.
///
/// Three-state modelling — loading, loaded, failed — is the default everywhere,
/// and it is wrong for this domain. **Stale is the fourth state, and it is the
/// one that matters here**: a forecast that is forty minutes old is far more use
/// to someone standing on the sand than a spinner or an error, but only if it
/// arrives carrying its age. The whole point of making it a separate case is
/// that a view cannot render stale data without having been handed the age to
/// label it with.
///
/// `SpotConditions` gets this treatment at the screen level and `BuoyStatus`
/// does the same job for one reading inside a screen, which is what lets a dead
/// buoy degrade its own strip without blanking the forecast above it.
public enum DataState<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    /// A previously good value, past its refresh window. `age` is in seconds and
    /// is not optional, because a stale value must never reach a view without it.
    case stale(Value, age: TimeInterval)
    case failed(reason: String)

    /// The value, whether it is current or old. Callers that must distinguish
    /// switch on the case instead — this is for the places that genuinely treat
    /// both the same, like deciding whether there is anything to lay out.
    public var value: Value? {
        switch self {
        case .loaded(let value): return value
        case .stale(let value, _): return value
        case .loading, .failed: return nil
        }
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    public var age: TimeInterval? {
        if case .stale(_, let age) = self { return age }
        return nil
    }

    public func map<T: Sendable>(_ transform: (Value) -> T) -> DataState<T> {
        switch self {
        case .loading: return .loading
        case .loaded(let value): return .loaded(transform(value))
        case .stale(let value, let age): return .stale(transform(value), age: age)
        case .failed(let reason): return .failed(reason: reason)
        }
    }
}

extension DataState: Equatable where Value: Equatable {}

public extension TimeInterval {
    /// Age in words, for the label a stale value has to carry.
    ///
    /// Words rather than a timestamp because the question a surfer is asking is
    /// "can I trust this", and "measured 40 minutes ago" answers it while
    /// "16:00" makes them do arithmetic at dawn.
    ///
    /// Hebrew is the product's primary locale; this returns the Hebrew phrasing
    /// and the view is expected to run it through the string catalogue for other
    /// locales.
    var ageInWordsHebrew: String {
        let seconds = max(0, self)
        if seconds < 60 { return "עכשיו" }

        // Truncating, not rounding: 90 seconds is "a minute ago", and rounding
        // it up to two would overstate the age of every reading in the app.
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return ago(minutes, one: "דקה", two: "שתי דקות", many: "דקות")
        }

        let hours = Int(seconds / 3600)
        if hours < 24 {
            return ago(hours, one: "שעה", two: "שעתיים", many: "שעות")
        }

        let days = Int(seconds / 86400)
        if days == 1 { return "אתמול" }
        return ago(days, one: "יום", two: "יומיים", many: "ימים")
    }

    /// Hebrew counts one, two and many separately, and the dual form is a word
    /// of its own rather than a number plus a noun. "לפני 2 שעות" is not
    /// something a Hebrew speaker says, and Hebrew is this app's primary locale,
    /// not a translation of the English.
    private func ago(_ count: Int, one: String, two: String, many: String) -> String {
        switch count {
        case 1: return "לפני \(one)"
        case 2: return "לפני \(two)"
        default: return "לפני \(count) \(many)"
        }
    }
}
