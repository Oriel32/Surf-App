import Foundation
import Testing
@testable import SurfCore

private func hour(
    _ h: Int,
    score: Int,
    daylight: Bool = true,
    day: Int = 29
) -> HourlyForecast {
    let conditions = SpotConditions(
        timestamp: .utc(2026, 8, day, h),
        spotID: "test-spot",
        waveHeightMeters: 0.8,
        periodSeconds: 8,
        band: .waistToChest,
        seaState: .glassy,
        windSpeedMPS: 3,
        windDirectionDegrees: 90,
        windRelation: .offshore,
        openSeaHeightMeters: 0.9,
        isSynthetic: false,
        isDaylight: daylight
    )
    return HourlyForecast(
        conditions: conditions,
        score: MatchScore(value: score, sport: .surfing),
        alerts: []
    )
}

@Suite("Daylight filtering")
struct DaylightTests {
    @Test("A perfect hour in the dark is not a window")
    func darkHoursCannotWin() {
        // Measured before this existed: the Week row reported a peak of 100 at
        // 03:00 local, and another at 20:00 - about an hour after sunset.
        // Neither was a wrong number. Both were useless ones.
        let night = (0..<6).map { hour($0, score: 100, daylight: false) }
        #expect(WindowFinder.bestWindow(in: night) == nil)
    }

    @Test("A window cannot be stitched across sunset")
    func noStitchingAcrossDark() throws {
        // Good at dusk, dark, then good again before dawn: two separate things,
        // and joining them would invent a window that runs through the night.
        let hours = [
            hour(17, score: 90), hour(18, score: 90),
            hour(19, score: 90, daylight: false), hour(20, score: 90, daylight: false)
        ]
        let window = try #require(WindowFinder.bestWindow(in: hours))
        #expect(window.start == Date.utc(2026, 8, 29, 17))
        // Ends at the close of the 18:00 hour, not carried into the dark ones.
        #expect(window.end == Date.utc(2026, 8, 29, 19))
    }

    @Test("The daily peak ignores hours nobody can surf")
    func peakIsDaylightOnly() {
        let mixed = [
            hour(3, score: 100, daylight: false),   // the 03:00 hundred
            hour(9, score: 55),
            hour(12, score: 61)
        ]
        let days = WindowFinder.dailyWindows(in: mixed)
        #expect(days.count == 1)
        #expect(days[0].peakScore == 61)
    }

    @Test("A source with no daylight data behaves exactly as before")
    func permissiveWithoutData() {
        // isDaylight defaults to true, so Stormglass and every existing fixture
        // keep working rather than silently reporting empty days.
        #expect(SpotConditions.fixture().isDaylight)
        let hours = [hour(2, score: 90), hour(3, score: 90)]
        #expect(WindowFinder.bestWindow(in: hours) != nil)
    }
}

@Suite("Star days")
struct StarTests {
    @Test("A star needs the score held, not merely touched")
    func needsConsecutiveHours() {
        // One brilliant hour between two poor ones is a chance, not a good day.
        let spike = [hour(8, score: 40), hour(9, score: 95), hour(10, score: 40)]
        #expect(!WindowFinder.isStarred(spike))

        let sustained = [hour(8, score: 40), hour(9, score: 95), hour(10, score: 88)]
        #expect(WindowFinder.isStarred(sustained))
    }

    @Test("Two good hours split by a bad one do not add up to a star")
    func runMustBeUnbroken() {
        let broken = [hour(8, score: 90), hour(9, score: 30), hour(10, score: 90)]
        #expect(!WindowFinder.isStarred(broken))
    }

    @Test("A star cannot be earned in the dark")
    func starNeedsDaylight() {
        let night = [hour(2, score: 100, daylight: false), hour(3, score: 100, daylight: false)]
        #expect(!WindowFinder.isStarred(night))
    }

    @Test("Good but not exceptional does not star")
    func thresholdHolds() {
        // 79 is a fine day. The star has to mean something rarer or it means
        // nothing at all.
        let good = [hour(8, score: 79), hour(9, score: 79), hour(10, score: 79)]
        #expect(!WindowFinder.isStarred(good))
    }

    @Test("Days report their own star alongside the window")
    func dailyWindowsCarryTheStar() {
        let starred = [hour(8, score: 90, day: 29), hour(9, score: 90, day: 29)]
        let ordinary = [hour(8, score: 50, day: 30), hour(9, score: 50, day: 30)]
        let days = WindowFinder.dailyWindows(in: starred + ordinary)
        #expect(days.count == 2)
        #expect(days[0].isStarred)
        #expect(!days[1].isStarred)
    }
}

@Suite("Gustiness")
struct GustTests {
    private func conditions(mean: Double, gust: Double?) -> SpotConditions {
        SpotConditions(
            timestamp: .utc(2026, 8, 29, 9),
            spotID: "test-spot",
            waveHeightMeters: 0.9,
            periodSeconds: 8,
            band: .waistToChest,
            seaState: .glassy,
            windSpeedMPS: mps(knots: mean),
            windDirectionDegrees: 90,
            windRelation: .offshore,
            openSeaHeightMeters: 1.0,
            isSynthetic: false,
            windGustMPS: gust.map { mps(knots: $0) },
            isDaylight: true
        )
    }

    @Test("No gust data reads as perfectly steady and costs nothing")
    func absentGustIsFree() {
        #expect(conditions(mean: 8, gust: nil).gustRatio == 1.0)
    }

    @Test("The ratio is what matters, not the gust speed")
    func ratioNotSpeed() {
        // 16 knots gusting off an 8-knot mean is shifty; 16 off a 14-knot mean
        // is merely windy. Same gust, different sea.
        #expect(abs(conditions(mean: 8, gust: 16).gustRatio - 2.0) < 1e-9)
        #expect(abs(conditions(mean: 14, gust: 16).gustRatio - 16.0/14.0) < 1e-9)
    }

    @Test("A ragged wind costs the score, a steady one does not")
    func raggedWindScoresLower() {
        // This is the case the app could not see: the mean stays inside every
        // light-wind band while the gusts push the sea around.
        let profile = UserProfile(sport: .surfing, skill: .intermediate)
        let steady = MatchScoreEngine.score(for: conditions(mean: 9, gust: 10), profile: profile).value
        let ragged = MatchScoreEngine.score(for: conditions(mean: 9, gust: 28), profile: profile).value
        #expect(steady > ragged)
        #expect(steady - ragged >= 20)
    }

    @Test("This coast's ordinary gustiness is not penalised")
    func typicalGustinessIsFree() {
        // Measured: the median gust ratio here is 1.85-2.04 every day of an
        // ordinary week. A penalty that every hour pays is not a penalty, it is
        // a uniform tax that discriminates nothing.
        #expect(ScoreTuning.surfing.gust.value(1.88) == 1.0)
        #expect(ScoreTuning.surfing.gust.value(3.1) < 0.3)
    }

    @Test("Gust never zeroes a session outright")
    func gustDegradesRatherThanCancels() {
        let profile = UserProfile(sport: .surfing, skill: .intermediate)
        #expect(MatchScoreEngine.score(for: conditions(mean: 9, gust: 40), profile: profile).value > 20)
    }
}
