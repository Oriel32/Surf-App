import Foundation

/// A contiguous run of hours worth going out for.
public struct SessionWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let peakScore: Int

    public init(start: Date, end: Date, peakScore: Int) {
        self.start = start
        self.end = end
        self.peakScore = peakScore
    }
}

/// Turns an hourly score curve into a plan.
///
/// This is what makes the difference between a forecast and an answer: "the best
/// window today is 06:00–09:00" is actionable in a way that twenty-four numbers
/// are not.
public enum WindowFinder {
    /// The longest contiguous run of hours at or above `minimumScore`, breaking
    /// ties by peak score.
    ///
    /// Returns `nil` when nothing clears the bar. That case must be reported
    /// plainly rather than by naming the least-bad hours — a window the app
    /// recommends is a window the user will drive to.
    /// The score at or above which an hour is worth driving to.
    ///
    /// Shared with `ScoreBand` so the recommendation and the colour cannot
    /// disagree: a row painted as usable that the window finder then refuses to
    /// recommend is the app telling the user two different things at once.
    public static let usableScore = 40

    public static func bestWindow(
        in hours: [HourlyForecast],
        minimumScore: Int = usableScore
    ) -> SessionWindow? {
        var best: SessionWindow?
        var runStart: Int?

        func closeRun(endingBefore index: Int) {
            guard let start = runStart else { return }
            let run = hours[start..<index]
            guard let first = run.first, let last = run.last,
                  let peak = run.map(\.score.value).max()
            else { return }
            let candidate = SessionWindow(
                start: first.conditions.timestamp,
                // The last qualifying hour is a start-of-hour stamp; the window
                // it describes runs to the end of that hour.
                end: last.conditions.timestamp.addingTimeInterval(3600),
                peakScore: peak
            )
            if isBetter(candidate, than: best) { best = candidate }
            runStart = nil
        }

        for (index, hour) in hours.enumerated() {
            if hour.score.value >= minimumScore {
                if runStart == nil { runStart = index }
            } else {
                closeRun(endingBefore: index)
            }
        }
        closeRun(endingBefore: hours.count)

        return best
    }

    private static func isBetter(_ candidate: SessionWindow, than current: SessionWindow?) -> Bool {
        guard let current else { return true }
        let candidateLength = candidate.end.timeIntervalSince(candidate.start)
        let currentLength = current.end.timeIntervalSince(current.start)
        if candidateLength != currentLength { return candidateLength > currentLength }
        return candidate.peakScore > current.peakScore
    }

    /// Groups an hourly series into days and finds each day's best window.
    ///
    /// The Week screen renders these, never a daily mean: a day that is glassy
    /// at dawn and blown out by noon averages to a number that is wrong at every
    /// hour it claims to describe.
    public static func dailyWindows(
        in hours: [HourlyForecast],
        calendar: Calendar = .israelStandard,
        minimumScore: Int = usableScore
    ) -> [(day: Date, window: SessionWindow?, peakScore: Int)] {
        let grouped = Dictionary(grouping: hours) { hour in
            calendar.startOfDay(for: hour.conditions.timestamp)
        }
        return grouped.keys.sorted().map { day in
            let dayHours = (grouped[day] ?? []).sorted { $0.conditions.timestamp < $1.conditions.timestamp }
            return (
                day: day,
                window: bestWindow(in: dayHours, minimumScore: minimumScore),
                peakScore: dayHours.map(\.score.value).max() ?? 0
            )
        }
    }
}

public extension Calendar {
    /// Days are grouped in local beach time, not UTC — a 05:00 dawn session
    /// belongs to the day the surfer thinks it does.
    static var israelStandard: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "Asia/Jerusalem") {
            calendar.timeZone = zone
        }
        return calendar
    }
}
