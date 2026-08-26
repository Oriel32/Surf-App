import Foundation
import Testing
@testable import SurfCore

@Suite("Translation to product vocabulary")
struct PresentationTests {
    private let conditions = SpotConditions.fixture(
        waveHeightMeters: 0.8,
        periodSeconds: 8,
        windSpeedMPS: mps(knots: 8),
        windRelation: .offshore,
        seaState: .glassy
    )
    private let score = MatchScore(value: 82, sport: .surfing)

    private var presentation: ConditionsPresentation {
        Translator.present(conditions, score: score)
    }

    @Test("Height is never shown without its slang, and never slang without the number")
    func heightAlwaysPairsWithSlang() {
        // Shipping a raw model value as "the wave height" is the failure mode
        // that kills trust; shipping the slang alone throws away the precision.
        let line = presentation.waveLine
        #expect(line.contains("0.8"))
        #expect(line.contains(WaveBand.waistToChest.hebrew))
        #expect(presentation.bandHebrew == WaveBand.waistToChest.hebrew)
        #expect(presentation.bandEnglish == "Waist to chest")
    }

    @Test("Units use the Hebrew geresh, never an ASCII apostrophe")
    func typographyUsesGeresh() {
        #expect(presentation.waveHeightText.contains(HebrewText.geresh))
        #expect(!presentation.waveHeightText.contains("'"))
        #expect(HebrewText.metersUnit == "\u{05DE}\u{05F3}")

        // The sea-state slang has the same rule.
        #expect(SeaState.choppy.hebrew.contains(HebrewText.geresh))
        #expect(!SeaState.choppy.hebrew.contains("'"))
    }

    @Test("Numeric runs are isolated so RTL layout cannot reverse them")
    func numbersStayLeftToRight() {
        // Without isolation, a decimal point or a hyphen reorders against the
        // surrounding Hebrew and renders 06:00-09:00 as 9:00-06:00.
        #expect(presentation.waveHeightText.hasPrefix(HebrewText.leftToRightIsolate))
        #expect(presentation.waveHeightText.contains(HebrewText.popDirectionalIsolate))
        #expect(presentation.scoreText?.contains(HebrewText.leftToRightIsolate) == true)

        let range = HebrewText.timeRange("06:00", "09:00")
        #expect(range.contains("06:00-09:00"))
        #expect(range.hasPrefix(HebrewText.leftToRightIsolate))
    }

    @Test("A number never sets the direction of the line it sits in")
    func numbersDoNotFlipTheLine() {
        // The bug this pins: LRM has bidi class L, so a line beginning with one
        // resolved LEFT-to-right under rule P2 and rendered inside out - the
        // Hebrew at one end, the height stranded at the other, away from its
        // unit. Isolates are skipped by P2, so the Hebrew decides.
        for line in [presentation.waveLine, presentation.windLine, presentation.waveHeightText] {
            #expect(!line.contains("\u{200E}"), "LRM would re-flip the line: \(line)")
            #expect(!line.contains("\u{200F}"))
        }

        // The first strong character outside any isolate must be Hebrew, which
        // is what makes the paragraph resolve right-to-left.
        #expect(firstStrongOutsideIsolates(presentation.waveLine) == .rightToLeft)
    }

    private enum Strength { case leftToRight, rightToLeft, none }

    /// Mirrors bidi rule P2: scan for the first strong character, skipping
    /// anything between an isolate initiator and its matching PDI.
    private func firstStrongOutsideIsolates(_ text: String) -> Strength {
        var depth = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x2066...0x2068: depth += 1
            case 0x2069: depth = max(0, depth - 1)
            default:
                guard depth == 0 else { continue }
                if (0x0590...0x08FF).contains(scalar.value) { return .rightToLeft }
                if (0x0041...0x005A).contains(scalar.value)
                    || (0x0061...0x007A).contains(scalar.value)
                    || scalar.value == 0x200E { return .leftToRight }
            }
        }
        return .none
    }

    @Test("VoiceOver gets one coherent sentence, not six fragments")
    func accessibilityLabelReadsAsMeaning() {
        // 1.0, not 0.8: the spoken label quotes the SETS. 0.8 m significant in
        // a Rayleigh sea puts the 1-in-10 wave at 1.02 m, and the sets are what
        // a surfer answers when asked how big it was.
        #expect(
            presentation.accessibilityLabel
                == "ציון 82, מותן עד חזה, 1.0 מטר, רוח מזרחית 8 קשר"
        )
    }

    @Test("Height is shown as a range, because surfers name sets")
    func heightIsARange() {
        // Every other forecast quotes "2-3 ft" for the same reason.
        #expect(presentation.waveHeightText.contains("0.8"))
        #expect(presentation.waveHeightText.contains("1.0"))
        #expect(presentation.waveHeightText.contains("-"))
    }

    @Test("The spoken label drops the abbreviations and the invisible marks")
    func accessibilityLabelIsSpeakable() {
        // A screen reader announcing מ׳ reads a letter, not "metres", and a
        // direction mark is noise in the middle of a word.
        let label = presentation.accessibilityLabel
        #expect(!label.contains(HebrewText.leftToRightIsolate))
        #expect(!label.contains(HebrewText.popDirectionalIsolate))
        #expect(!label.contains("\u{200E}"))
        #expect(!label.contains(HebrewText.geresh))
        #expect(label.contains("מטר"))
    }

    @Test("Wind is named by direction and strength, with the relation kept separate")
    func windCarriesDirectionAndRelation() {
        // The relation word outranks the arrow and the number in the layout:
        // "offshore" is the fact that changes behaviour.
        // Built from the helper rather than hardcoding the control characters,
        // so changing how numbers are isolated cannot silently break this.
        #expect(presentation.windLine == "רוח מזרחית \(HebrewText.ltr("8")) קשר")
        #expect(presentation.windDirection == .east)
        #expect(presentation.windStrength == .weak)
        #expect(presentation.windRelationHebrew == WindRelation.offshore.hebrew)
    }

    @Test("The score arrives with its band and its token")
    func scoreCarriesBandAndToken() {
        #expect(presentation.scoreBand == .excellent)
        #expect(presentation.scoreToken == .hero)
        #expect(presentation.seaStateToken == .hero)
        #expect(presentation.seaStateHebrew == SeaState.glassy.hebrew)
    }

    @Test("An unscored hour still presents its conditions")
    func scoreIsOptional() {
        let bare = Translator.present(conditions)
        #expect(bare.scoreText == nil)
        #expect(bare.scoreBand == nil)
        #expect(bare.scoreToken == nil)
        #expect(bare.waveLine == presentation.waveLine)
    }

    @Test("Eilat's synthetic values are labelled wherever they appear")
    func syntheticValuesAreLabelled() {
        // Global wave models do not resolve the gulf, so these numbers come from
        // local wind. Saying so is not optional styling.
        let eilat = Spot.fixture(basin: .gulfOfEilat)
        let synthetic = WaveTransform.transform(
            .fixture(windSpeedMPS: mps(knots: 12)), at: eilat
        )
        let presented = Translator.present(synthetic)

        #expect(synthetic.isSynthetic)
        #expect(presented.derivationNoticeHebrew != nil)
        #expect(presented.accessibilityLabel.contains("נגזר מקומית"))

        #expect(presentation.derivationNoticeHebrew == nil)
    }

    @Test("An hourly forecast presents the same way as its parts")
    func presentsAnHourlyForecast() {
        let hour = HourlyForecast(conditions: conditions, score: score, alerts: [])
        #expect(Translator.present(hour) == presentation)
    }
}

@Suite("Compass vocabulary")
struct CompassPointTests {
    @Test("North wraps across zero without a special case in the caller")
    func northWraps() {
        #expect(CompassPoint.point(forDegrees: 0) == .north)
        #expect(CompassPoint.point(forDegrees: 10) == .north)
        #expect(CompassPoint.point(forDegrees: 350) == .north)
        #expect(CompassPoint.point(forDegrees: 359.9) == .north)
    }

    @Test("The cardinal bearings name themselves")
    func cardinals() {
        #expect(CompassPoint.point(forDegrees: 90) == .east)
        #expect(CompassPoint.point(forDegrees: 180) == .south)
        #expect(CompassPoint.point(forDegrees: 270) == .west)
        #expect(CompassPoint.point(forDegrees: 45) == .northEast)
        #expect(CompassPoint.point(forDegrees: 225) == .southWest)
    }

    @Test("An unnormalised bearing is wrapped before it is named")
    func normalisesFirst() {
        #expect(CompassPoint.point(forDegrees: -90) == .west)
        #expect(CompassPoint.point(forDegrees: 450) == .east)
    }

    @Test("Every point and every relation is localised")
    func everythingIsLocalised() {
        for point in CompassPoint.allCases {
            #expect(!point.hebrewAdjective.isEmpty)
            #expect(!point.english.isEmpty)
        }
        for relation in WindRelation.allCases {
            #expect(!relation.hebrew.isEmpty)
            #expect(!relation.english.isEmpty)
        }
    }
}
