import Foundation
import Testing
@testable import SurfCore

/// The 2026-08-29 morning session at Bat Yam, hour by hour.
///
/// ## What happened
/// A surfer entered the water at 09:30 and reported: waves building; by 10:00
/// still building but with *"a little bit of current and wind that made the sea
/// bit choppy and wavy"*, a good wave every few minutes; and by 10:20 *"the
/// current and the wind became much higher and the conditions were not very
/// good — wavy sea with lot of current and disorganized waves."*
///
/// ## What the engine said before this suite existed
/// `סביר` at 09:00, 10:00 **and** 11:00, first `צ׳ופי` only at noon — two hours
/// after the water turned. The displayed beach height *rose* through the whole
/// session, 0.62 → 0.66 m, and so did the period, 7.0 → 7.7 s. Every headline
/// number moved the wrong way or not at all, and the score held flat until the
/// wind relation happened to flip a bin at 11:00.
///
/// ## Why
/// The mean wind never left the 0-10 kt band the domain rules call ideal for
/// surfing. What changed was the *mixture*: the wind wave went from 11% of the
/// energy at the break to 24%, while the swell under it was flat to falling. The
/// engine summed the two trains into one height and threw the split away, so
/// nothing downstream could see the one thing that was actually happening.
///
/// Values are the real Open-Meteo `best_match` output for 32.017/34.735 on the
/// day. See `calibration/bat-yam-comparison.md`, observation #3.
@Suite("Bat Yam, 2026-08-29 — a session the model called fine")
struct BatYamAugust29Tests {
    /// The catalogued spot, not `Spot.fixture`'s defaults: the 0.72 exposure and
    /// the 270° normal are what make these numbers reproducible against smoke.
    private var batYam: Spot {
        Spot(
            id: "bat-yam",
            nameHebrew: "בת ים",
            nameEnglish: "Bat Yam",
            latitude: 32.0171,
            longitude: 34.7403,
            basin: .mediterranean,
            exposureCoefficient: 0.72,
            shorelineNormalDegrees: 270,
            breakDepthMeters: 2.0,
            buoyStationID: "hadera"
        )
    }

    /// One hour as the model reported it, with both partitions.
    private func hour(
        _ localHour: Int,
        swell: (h: Double, tp: Double, dir: Double),
        windWave: (h: Double, tp: Double, dir: Double),
        combined: Double,
        windKnots: Double,
        windFrom: Double,
        gustKnots: Double
    ) -> RawMarineSample {
        RawMarineSample(
            // Israel is UTC+3 in August.
            timestamp: .utc(2026, 8, 29, localHour - 3),
            waveHeightMeters: combined,
            wavePeriodSeconds: swell.tp,
            waveDirectionDegrees: swell.dir,
            primarySwell: SwellComponent(
                heightMeters: swell.h,
                periodSeconds: swell.tp * 0.78,
                peakPeriodSeconds: swell.tp,
                directionDegrees: swell.dir
            ),
            windWave: SwellComponent(
                heightMeters: windWave.h,
                periodSeconds: windWave.tp * 0.78,
                peakPeriodSeconds: windWave.tp,
                directionDegrees: windWave.dir
            ),
            windSpeedMPS: Units.metersPerSecond(fromKnots: windKnots),
            windDirectionDegrees: windFrom,
            windGustMPS: Units.metersPerSecond(fromKnots: gustKnots)
        )
    }

    private var nineAM: RawMarineSample {
        hour(9,
             swell: (0.72, 6.95, 290), windWave: (0.34, 2.65, 220),
             combined: 0.82, windKnots: 8.0, windFrom: 193, gustKnots: 15.6)
    }

    private var tenAM: RawMarineSample {
        hour(10,
             swell: (0.70, 7.65, 290), windWave: (0.44, 2.45, 225),
             combined: 0.88, windKnots: 9.0, windFrom: 204, gustKnots: 17.7)
    }

    private var elevenAM: RawMarineSample {
        hour(11,
             swell: (0.68, 7.65, 289), windWave: (0.52, 3.25, 229),
             combined: 0.92, windKnots: 10.6, windFrom: 223, gustKnots: 20.8)
    }

    // MARK: - The assertion this whole suite exists for

    @Test("The sea reads choppy from 10:00, the hour the surfer said it turned")
    func choppyWhenItWasChoppy() {
        let nine = WaveTransform.transform(nineAM, at: batYam)
        let ten = WaveTransform.transform(tenAM, at: batYam)
        let eleven = WaveTransform.transform(elevenAM, at: batYam)

        // 09:30 in the water: building, no complaint about the surface.
        #expect(nine.seaState == .fair)
        // "made the sea bit choppy and wavy"
        #expect(ten.seaState == .choppy)
        // "wavy sea with lot of current and disorganized waves"
        #expect(eleven.seaState == .choppy)
    }

    // MARK: - Why the old rules could not see it

    @Test("The mean wind stayed inside the band the rules call ideal all morning")
    func theWindNeverLookedLikeTheProblem() {
        for sample in [nineAM, tenAM, elevenAM] {
            let knots = Units.knots(fromMetersPerSecond: sample.windSpeedMPS)
            #expect(knots <= 10.7)
            // Below `onshoreChopKnots`, so the pre-existing chop rule could
            // never have fired — and for the first two hours the wind is not
            // even onshore.
            #expect(knots < SeaStateRules.standard.onshoreChopKnots)
        }
        // And the direction only crosses out of side-shore in the last hour.
        #expect(WaveTransform.transform(nineAM, at: batYam).windRelation == .sideShore)
        #expect(WaveTransform.transform(tenAM, at: batYam).windRelation == .sideShore)
    }

    @Test("Total height rises while the swell under it falls")
    func theHeadlineNumberMovedTheWrongWay() {
        let hours = [nineAM, tenAM, elevenAM].map { WaveTransform.transform($0, at: batYam) }

        // What the app displays: up, and up again. Reads as improving.
        #expect(hours[0].waveHeightMeters < hours[1].waveHeightMeters)
        #expect(hours[1].waveHeightMeters < hours[2].waveHeightMeters)

        // What could actually be ridden: flat, then down.
        let swell = hours.compactMap(\.swellHeightMeters)
        #expect(swell.count == 3)
        #expect(swell[2] < swell[0])

        // The entire rise is chop.
        let chop = hours.compactMap(\.windSeaHeightMeters)
        #expect(chop[0] < chop[1])
        #expect(chop[1] < chop[2])
    }

    @Test("The reported period improves through a session that was falling apart")
    func periodIsTrueAndMisleading() {
        let nine = WaveTransform.transform(nineAM, at: batYam)
        let eleven = WaveTransform.transform(elevenAM, at: batYam)

        // Read off the dominant train, and the swell stayed dominant, so the
        // number rises. It is not wrong — it is unable to say what changed,
        // which is why `chop` is a separate score term rather than a correction
        // applied to this one.
        #expect(eleven.periodSeconds > nine.periodSeconds)
    }

    // MARK: - The measurement that did track it

    @Test("Chop energy share doubles across the session")
    func chopShareIsTheSignal() {
        let shares = [nineAM, tenAM, elevenAM]
            .map { WaveTransform.transform($0, at: batYam) }
            .compactMap(\.windSeaEnergyShare)
        #expect(shares.count == 3)

        // Measured at the break: 11.3% / 18.4% / 23.9%.
        #expect(abs(shares[0] - 0.113) < 0.01)
        #expect(abs(shares[1] - 0.184) < 0.01)
        #expect(abs(shares[2] - 0.239) < 0.01)

        // The threshold sits between the first two, which is what puts the first
        // choppy hour at 10:00 rather than 09:00 or noon.
        #expect(shares[0] < SeaStateRules.standard.chopEnergyShare)
        #expect(shares[1] >= SeaStateRules.standard.chopEnergyShare)
    }

    @Test("The share at the beach is well below the share offshore")
    func theTransformChangesTheMixture() {
        // Open sea at 10:00: 0.44 m of chop under 0.70 m of swell is 28% of the
        // energy. At the break it is 18%, because a 7.65 s swell shoals up over
        // the bar and a 2.45 s chop does not.
        //
        // A threshold set on the open-sea number would fire an hour early. This
        // is why `windSeaEnergyShare` is computed after the transform.
        let openSea = (0.44 * 0.44) / (0.70 * 0.70 + 0.44 * 0.44)
        let atBeach = WaveTransform.transform(tenAM, at: batYam).windSeaEnergyShare ?? 0
        #expect(abs(openSea - 0.283) < 0.01)
        #expect(atBeach < openSea - 0.05)
    }

    @Test("Swell and chop arrive from opposite sides of the shore normal")
    func confusedWater() {
        // Swell from 290° is 20° north of the 270° normal; the chop from 225° is
        // 45° south of it. Two trains pushing the water opposite ways along the
        // beach is what "disorganized waves" describes.
        #expect(WaveTransform.transform(tenAM, at: batYam).isCrossSea)
        #expect(WaveTransform.transform(elevenAM, at: batYam).isCrossSea)

        // Not flagged at 09:00: the geometry is the same, but there is not yet
        // enough chop for it to matter, and a flag that is always on says nothing.
        #expect(!WaveTransform.transform(nineAM, at: batYam).isCrossSea)
    }

    // MARK: - What the user is shown

    @Test("The score holds through 10:00 and then falls, which is the session as described")
    func theScoreDecays() {
        let profile = UserProfile(sport: .surfing, skill: .intermediate)
        let scores = [nineAM, tenAM, elevenAM]
            .map { WaveTransform.transform($0, at: batYam) }
            .map { MatchScoreEngine.score(for: $0, profile: profile).value }

        // 09:00 → 10:00 is deliberately NOT asserted to fall. The first version
        // of this test demanded a monotone decline and failed here, and the
        // report is why the test was wrong rather than the engine: at 10:00 the
        // surfer still had "good waves every few minutes". The sea was bigger
        // and longer-period as well as choppier, and those genuinely trade off.
        // The collapse is reported at 10:20 — between these two model hours.
        #expect(abs(scores[0] - scores[1]) <= 6)

        // 10:00 → 11:00 is the one that has to move. Before the chop term this
        // fall existed but arrived entirely through the wind relation crossing
        // from side-shore into cross-onshore, a bin flip that happens to land on
        // the right hour here and would not on a day the wind held its bearing.
        #expect(scores[1] - scores[2] >= 15)
    }

    @Test("The chop term is what carries that decay, not the wind bin flipping")
    func decayIsAttributable() {
        let profile = UserProfile(sport: .surfing, skill: .intermediate)
        let nine = MatchScoreEngine.score(
            for: WaveTransform.transform(nineAM, at: batYam), profile: profile
        )
        let ten = MatchScoreEngine.score(
            for: WaveTransform.transform(tenAM, at: batYam), profile: profile
        )

        // Both hours are side-shore at a wind speed the curve barely notices, so
        // before the chop term existed these two scored within a couple of points
        // of each other. The separation has to come from `chop`.
        #expect((nine.components["chop"] ?? 0) > (ten.components["chop"] ?? 0))
        #expect(abs((nine.components["wind"] ?? 0) - (ten.components["wind"] ?? 0)) < 0.1)
    }

    @Test("A paddler is told the current, and it costs them their score")
    func supFeelsTheCurrent() throws {
        let ten = WaveTransform.transform(tenAM, at: batYam)
        let current = try #require(ten.longshoreCurrentSpeedMPS)

        // Enough water moving along the beach to be worth naming.
        #expect(current > 0.3)

        // Provisional magnitude, so this asserts the coupling exists rather than
        // pinning a number: the same sea with still water scores higher for SUP.
        let profile = UserProfile(sport: .sup, skill: .intermediate)
        let withCurrent = MatchScoreEngine.score(for: ten, profile: profile).value
        let stillWater = MatchScoreEngine.score(
            for: SpotConditions(
                timestamp: ten.timestamp,
                spotID: ten.spotID,
                waveHeightMeters: ten.waveHeightMeters,
                periodSeconds: ten.periodSeconds,
                band: ten.band,
                seaState: ten.seaState,
                windSpeedMPS: ten.windSpeedMPS,
                windDirectionDegrees: ten.windDirectionDegrees,
                windRelation: ten.windRelation,
                openSeaHeightMeters: ten.openSeaHeightMeters,
                isSynthetic: false,
                longshoreCurrentMPS: 0
            ),
            profile: profile
        ).value
        #expect(stillWater > withCurrent)
    }

    // MARK: - The half-plane guard

    @Test("A wind wave from behind the shoreline is dropped, not turned into a NaN")
    func shadowedTrainIsDropped() {
        // 02:00 that night carried a wind wave from 179° at a beach whose normal
        // is 270° — 91° away, just past the half-plane. `refractionCoefficient`
        // returns nil there and the train contributes nothing.
        //
        // Pinned because an independent reimplementation of this transform,
        // written to check the engine's own numbers, produced NaN at exactly
        // this hour by taking `sqrt(cos θ)` without the guard. The engine was
        // right and the guard is load-bearing; nothing covered this boundary.
        let shadowed = hour(2,
                            swell: (0.66, 6.30, 289), windWave: (0.02, 1.50, 179),
                            combined: 0.66, windKnots: 2.7, windFrom: 188, gustKnots: 5.1)
        let conditions = WaveTransform.transform(shadowed, at: batYam)

        #expect(conditions.waveHeightMeters.isFinite)
        #expect(conditions.windSeaHeightMeters == 0)
        #expect(conditions.windSeaEnergyShare == 0)
        #expect(WaveTransform.refractionCoefficient(
            periodSeconds: 1.5, depthMeters: 2.0, incidentAngleDegrees: 91
        ) == nil)
    }
}
