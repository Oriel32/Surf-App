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

/// One day, as the Week screen promises it.
///
/// `peakHour` is carried rather than left for the caller to re-derive, and that
/// is the whole point of the type. Every caller that recomputed it took the max
/// over **all** hours while `peakScore` came from daylight only, so on any day
/// whose best hour fell in the dark the score described one hour and the height
/// beside it described another. The Week row and the smoke test both shipped
/// that. A day is a promise about a time of day, so the hour it promises travels
/// with it.
public struct DayOutlook: Sendable, Equatable {
    public let day: Date
    public let window: SessionWindow?
    public let peakScore: Int
    public let isStarred: Bool
    /// The daylight hour `peakScore` was taken from. `nil` only for a day with
    /// no lit hours at all.
    public let peakHour: HourlyForecast?

    public init(
        day: Date,
        window: SessionWindow?,
        peakScore: Int,
        isStarred: Bool,
        peakHour: HourlyForecast?
    ) {
        self.day = day
        self.window = window
        self.peakScore = peakScore
        self.isStarred = isStarred
        self.peakHour = peakHour
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

    /// The score a day must hold, for `starHours` consecutive daylight hours,
    /// to be worth marking as special.
    ///
    /// A star has to be rare or it says nothing. Two hours rather than one so a
    /// single fluke hour cannot earn it, and daylight-only because a perfect
    /// 03:00 is not a session.
    public static let starScore = 80
    public static let starHours = 2

    /// Only hours a person could actually be in the water.
    ///
    /// Measured on this coast before this existed: the Week screen was
    /// reporting a peak of 100 at 03:00 local, and another at 20:00 — nearly an
    /// hour after sunset. Neither was a wrong number; both were useless ones.
    private static func daylight(_ hours: [HourlyForecast]) -> [HourlyForecast] {
        let lit = hours.filter(\.conditions.isDaylight)
        // A source with no daylight data marks everything lit, so an empty
        // result means the day genuinely has no surfable hours rather than that
        // the filter misfired.
        return lit
    }

    public static func bestWindow(
        in hours: [HourlyForecast],
        minimumScore: Int = usableScore
    ) -> SessionWindow? {
        // Dark hours are dropped before the run search rather than after, so a
        // run cannot be stitched across sunset.
        let hours = daylight(hours)
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
    ) -> [DayOutlook] {
        let grouped = Dictionary(grouping: hours) { hour in
            calendar.startOfDay(for: hour.conditions.timestamp)
        }
        return grouped.keys.sorted().map { day in
            let dayHours = (grouped[day] ?? []).sorted { $0.conditions.timestamp < $1.conditions.timestamp }
            // The peak is taken over daylight only, for the same reason the
            // window is: a row promising 100 at three in the morning is a row
            // nobody can act on.
            let lit = daylight(dayHours)
            let peak = lit.max { $0.score.value < $1.score.value }
            return DayOutlook(
                day: day,
                window: bestWindow(in: dayHours, minimumScore: minimumScore),
                peakScore: peak?.score.value ?? 0,
                isStarred: isStarred(dayHours),
                peakHour: peak
            )
        }
    }

    /// Whether a day is worth a star: `starScore` or better, held for
    /// `starHours` consecutive daylight hours.
    ///
    /// Consecutive matters. A day that touches 85 at dawn, collapses, and
    /// touches 85 again at dusk is two brief chances, not a good day, and
    /// counting total hours rather than a run would call it one.
    public static func isStarred(_ hours: [HourlyForecast]) -> Bool {
        var run = 0
        for hour in daylight(hours).sorted(by: { $0.conditions.timestamp < $1.conditions.timestamp }) {
            if hour.score.value >= starScore {
                run += 1
                if run >= starHours { return true }
            } else {
                run = 0
            }
        }
        return false
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
