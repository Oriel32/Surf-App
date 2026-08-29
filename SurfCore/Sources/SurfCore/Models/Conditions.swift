import Foundation

/// Wave height expressed the way surfers actually measure it — against the body
/// standing on the board, not against a ruler.
///
/// ## Where this table comes from
/// Not from `surf_research.md`, which was measured against GoSurf and found two
/// to three bands too generous: on 2026-08-27 at Bat Yam it named a 0.48 m sea
/// `מותן עד חזה` where GoSurf — the local market leader, whose swell column
/// agrees with our model input and with the ISRAMAR buoy to within 12 cm —
/// called the same hour `ים גלי`, no anatomical term at all.
///
/// This ladder is GoSurf's own, published as:
///
/// > מצבי הים האפשריים הם: פלטה, ים נוח, ים גלי, גלים בגובה —
/// > קרסול, ברך, מותן, חזה, כתף, ראש, פעמיים ראש
///
/// Seven single terms, not paired ranges, and they begin only where waves start
/// to break. The boundaries are anchored on GoSurf's stated break point of
/// 50 cm and reproduce both of their words from that day without tuning.
/// See `calibration/bat-yam-comparison.md`.
public enum WaveBand: String, Sendable, Equatable, CaseIterable {
    // Below the break point there is no wave to name a body part after. These
    // three are sea *states*, and GoSurf uses them in the same column.
    case flat
    case calmSea
    case wavySea

    case ankle
    case knee
    case waist
    case chest
    case shoulder
    case head
    case doubleHead

    /// Where the water stops being flat and starts being a sea, metres.
    /// Below this, no wind texture makes it anything but `פלטה`.
    public static let flatCeilingMeters = 0.10

    /// The ceiling for `ים נוח`, metres. Above it a sub-breaking sea reads
    /// `ים גלי` however smooth the surface is.
    ///
    /// Measured, not assumed: on 2026-08-27 GoSurf called Bat Yam `ים גלי` at
    /// 06:00 in a 4 km/h wind — glass, by any texture rule — and again at 21:00.
    /// Our beach heights those hours were 0.46 m and 0.37 m. So `ים נוח` is not
    /// "smooth", it is "small *and* smooth", and its ceiling sits below 0.37.
    public static let calmSeaCeilingMeters = 0.30

    /// The anatomical ladder, as one readable table a local surfer can check
    /// line by line. `RuleTable` rejects a non-ascending edit outright, so the
    /// bands cannot be left overlapping or out of order by a later change.
    ///
    /// Only ever consulted for a sea that *is* breaking — everything below the
    /// break point is decided by `band(forHeightMeters:periodSeconds:seaState:)`
    /// before this is reached. That is why the ladder starts at zero rather than
    /// restating the 50 cm break point: stating it here as well made a
    /// long-period 0.45 m wave both break (`SurfBreaking` said yes at 10 s) and
    /// land in the sub-breaking row, which is a contradiction the table cannot
    /// be allowed to express.
    public static let table = RuleTable<WaveBand>([
        .init(from: 0, .ankle),
        .init(from: 0.70, .knee),
        .init(from: 0.95, .waist),
        .init(from: 1.20, .chest),
        .init(from: 1.45, .shoulder),
        .init(from: 1.70, .head),
        .init(from: 2.20, .doubleHead)
    ])

    /// Lower bound in metres, inclusive. Read back from the table, so a
    /// threshold is never stated in two places that can drift apart.
    public var lowerBoundMeters: Double {
        Self.table.lowerBound(of: self) ?? 0
    }

    /// Whether this band names a rideable wave rather than a state of the sea.
    public var isBreakingSurf: Bool {
        switch self {
        case .flat, .calmSea, .wavySea: return false
        default: return true
        }
    }

    public var hebrew: String {
        switch self {
        case .flat: return "פלטה"
        case .calmSea: return "ים נוח"
        case .wavySea: return "ים גלי"
        case .ankle: return "קרסול"
        case .knee: return "ברך"
        case .waist: return "מותן"
        case .chest: return "חזה"
        case .shoulder: return "כתף"
        case .head: return "ראש"
        case .doubleHead: return "פעמיים ראש"
        }
    }

    public var english: String {
        switch self {
        case .flat: return "Flat"
        case .calmSea: return "Calm sea"
        case .wavySea: return "Wavy sea"
        case .ankle: return "Ankle"
        case .knee: return "Knee"
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .shoulder: return "Shoulder"
        case .head: return "Head"
        case .doubleHead: return "Double head"
        }
    }

    /// The band for a sea, given what it is doing as well as how big it is.
    ///
    /// - Parameter seaState: only separates `ים נוח` from `ים גלי` below the
    ///   break point, which is a question about texture and not about height.
    ///   It never affects which anatomical term is chosen.
    public static func band(
        forHeightMeters height: Double,
        periodSeconds: Double,
        seaState: SeaState
    ) -> WaveBand {
        guard height >= flatCeilingMeters else { return .flat }

        guard SurfBreaking.breaks(heightMeters: height, periodSeconds: periodSeconds) else {
            // There is water moving but nothing to ride. `ים נוח` is the
            // swimmer's sea — small *and* smooth. Anything bigger is `ים גלי`
            // no matter how clean the surface, which is the call GoSurf makes.
            let smooth = seaState == .glassy || seaState == .flat
            return (smooth && height < calmSeaCeilingMeters) ? .calmSea : .wavySea
        }

        return table.value(for: height)
    }
}

/// When a sea has waves in it that actually break.
///
/// GoSurf states the rule as *"גלים נשברים מ-50 ס״מ עם תלות במחזור הגל"* —
/// waves break from 50 cm, depending on the wave period. Both halves matter: a
/// 0.6 m wind slop at 4 s is a lumpy sea with nothing to catch, and a 0.4 m
/// groundswell at 12 s stands up and peels.
///
/// Keyed to energy rather than to height alone, because energy is exactly where
/// height and period combine the way the physics combines them — and because
/// `SpotConditions.energyKilowattsPerMetre` already computes it.
public enum SurfBreaking {
    /// `0.5 · H² · T` at the break point 0.50 m / 6.0 s — the median period
    /// measured on this coast, so the anchor is a real local sea rather than a
    /// textbook one.
    public static let thresholdKilowattsPerMetre = 0.75

    /// The smallest wave that breaks at this period, metres.
    /// 0.61 m at 4 s · 0.50 m at 6 s · 0.43 m at 8 s · 0.35 m at 12 s.
    public static func minimumHeightMeters(periodSeconds period: Double) -> Double {
        guard period > 0 else { return .infinity }
        return (thresholdKilowattsPerMetre / (0.5 * period)).squareRoot()
    }

    public static func breaks(heightMeters height: Double, periodSeconds period: Double) -> Bool {
        guard height > 0, period > 0 else { return false }
        return 0.5 * height * height * period >= thresholdKilowattsPerMetre
    }
}

/// The texture of the water surface — what the wind is doing to the face.
public enum SeaState: String, Sendable, Equatable, CaseIterable {
    case flat
    case glassy
    case fair
    case choppy

    public var hebrew: String {
        switch self {
        case .flat: return "פלטה"
        case .glassy: return "גלאסי"
        // Not from the research, which names only flat/glassy/choppy. A binary
        // glassy-or-choppy misdescribes most real days, so this middle state
        // uses plain Hebrew rather than invented slang. Confirm the wording.
        case .fair: return "סביר"
        case .choppy: return "צ׳ופי"
        }
    }

    public var english: String {
        switch self {
        case .flat: return "Flat"
        case .glassy: return "Glassy"
        case .fair: return "Fair"
        case .choppy: return "Choppy"
        }
    }
}

/// The transformed, spot-specific, presentable conditions.
///
/// This — not `RawMarineSample` — is what the UI renders.
public struct SpotConditions: Sendable, Equatable {
    public let timestamp: Date
    public let spotID: String

    /// Breaking wave height at this spot, metres, after sheltering, refraction
    /// and shoaling.
    ///
    /// **Not clipped to the depth-limited breaking height.** A spot's
    /// `breakDepthMeters` is one nominal figure standing in for a whole surf
    /// zone, and clipping the reported height against it flattened every big day
    /// to the same ceiling: on 2026-08-27 the 29th and 30th of August both came
    /// out at exactly 1.60 m from open-sea inputs of 1.76 m and 1.94 m, while
    /// GoSurf separated the same two days as 90 cm and 200 cm. A week that
    /// cannot tell its biggest day from a mediocre one sends people to the beach
    /// on the wrong morning. See `calibration/bat-yam-comparison.md`.
    ///
    /// The constraint still exists and is still enforced — on the score, via
    /// `rideableHeightMeters` — because how big a wave *is* and how much of it a
    /// sandbar can hold up are two different questions.
    public let waveHeightMeters: Double
    public let periodSeconds: Double
    public let band: WaveBand
    public let seaState: SeaState

    /// The two halves of `waveHeightMeters`, each transformed on its own
    /// geometry: groundswell, and the locally generated wind wave.
    ///
    /// `waveHeightMeters` is their quadrature sum, which means a building chop
    /// *raises* it — on 2026-08-29 at Bat Yam the reported beach height climbed
    /// 0.62 → 0.66 m through a session that was deteriorating, because the swell
    /// under it was falling 0.583 → 0.574 m while the chop doubled. The combined
    /// number is not wrong; it is just unable to say which of those two happened,
    /// and the difference is the whole session.
    ///
    /// `nil` when the source does not partition the sea, and for the synthetic
    /// Gulf of Eilat path — deliberately, so that every rule keyed to the split
    /// is a no-op there rather than silently calling a calm gulf morning choppy.
    public let swellHeightMeters: Double?
    public let windSeaHeightMeters: Double?

    /// Swell and wind wave arriving from opposite sides of the shore normal,
    /// with enough chop present to matter.
    ///
    /// Two trains forcing the water in opposite directions along the beach is
    /// confused, disorganised water — which is the phrase the 2026-08-29 report
    /// used, and which neither height nor period nor wind speed can express on
    /// its own. At Bat Yam that morning the swell came from 290° (20° north of
    /// the 270° normal) and the chop from 220-229°, 41-50° south of it.
    public let isCrossSea: Bool

    /// Signed longshore current at the break, m/s — positive flowing toward
    /// `shorelineNormalDegrees + 90`. See `LongshoreCurrent`, including its
    /// standing caveat that the magnitude is provisional.
    ///
    /// `nil` for the synthetic Gulf of Eilat path, which models no surf zone for
    /// a current to run in.
    public let longshoreCurrentMPS: Double?

    /// Unsigned current speed, m/s — what a readout shows. Direction is carried
    /// by the sign of `longshoreCurrentMPS`.
    public var longshoreCurrentSpeedMPS: Double? {
        longshoreCurrentMPS.map(abs)
    }

    public let windSpeedMPS: Double
    public let windDirectionDegrees: Double
    public let windRelation: WindRelation

    /// Gust speed, m/s, where the source reports it.
    public let windGustMPS: Double?

    /// Whether this hour is between sunrise and sunset at the spot. A forecast
    /// that recommends 03:00 is not wrong, it is useless.
    public let isDaylight: Bool

    /// The untransformed open-sea height, kept so the detail view can show its
    /// work. Displaying both is what proves the app transformed the data rather
    /// than reprinting a model.
    public let openSeaHeightMeters: Double

    /// The open-sea **swell partition**, untransformed — the Layer 2 "raw
    /// open-sea swell" the UI spec asks for, and the only model quantity
    /// directly comparable to an offshore buoy.
    ///
    /// `openSeaHeightMeters` above is the combined sea, which includes wind
    /// wave. Against an ISRAMAR reading those are different quantities and the
    /// difference is not a model error: see `CalibrationRecord`.
    ///
    /// `nil` where the source did not partition.
    public let openSeaSwellHeightMeters: Double?
    public let openSeaSwellPeriodSeconds: Double?

    /// True when values were synthesised from local wind rather than taken from
    /// a wave model — the Gulf of Eilat case. The UI must label these.
    public let isSynthetic: Bool

    public let seaSurfaceTemperatureC: Double?
    public let airTemperatureC: Double?

    /// Sea level relative to mean, metres. Low in the hierarchy on purpose:
    /// the Mediterranean tidal range is a few dozen centimetres, so this
    /// informs where a wave breaks rather than whether to go.
    public let seaLevelMeters: Double?

    /// `0.78 × depth` at this spot for this hour — the tallest wave the sandbar
    /// can hold up before it collapses forward.
    ///
    /// Carried rather than applied, so the layer that needs it can ask for it.
    /// Zero for the synthetic Gulf of Eilat path, which models no bar.
    public let breakingLimitMeters: Double

    /// The part of the wave that is actually rideable here: the reported height,
    /// or what the bar can hold, whichever is smaller.
    ///
    /// This is what the Match Score reads. A 2 m swell arriving over a 1.6 m
    /// ceiling is genuinely 2 m of water moving and genuinely a closeout, and
    /// the score is the layer that is being asked "is it worth surfing", not
    /// "how big is it".
    public var rideableHeightMeters: Double {
        breakingLimitMeters > 0 ? min(waveHeightMeters, breakingLimitMeters) : waveHeightMeters
    }

    /// Whether the bar, rather than the incoming sea, is deciding the ride.
    /// A day this is true is a day of closeouts, however big the number reads.
    public var isDepthLimited: Bool {
        breakingLimitMeters > 0 && waveHeightMeters > breakingLimitMeters
    }

    public var windSpeedKnots: Double {
        Units.knots(fromMetersPerSecond: windSpeedMPS)
    }

    /// The surf as a range: the significant breaking height through to the sets.
    /// `waveHeightMeters` stays the physical value; this is how it is spoken.
    public var surfRange: SurfRange {
        SurfRange(significantMeters: waveHeightMeters)
    }

    /// Deep-water wave power at the break, kW/m. The quantity Surfline and
    /// Magicseaweed lead with, because height alone cannot separate a 1 m
    /// groundswell from 1 m of chop.
    public var energyKilowattsPerMetre: Double {
        0.5 * waveHeightMeters * waveHeightMeters * periodSeconds
    }

    /// The same power, from the part of the wave the bar can actually hold up.
    /// What the score reads, so a closeout cannot bank the energy of a wave that
    /// never stands. Identical to `energyKilowattsPerMetre` when not depth-limited.
    public var rideableEnergyKilowattsPerMetre: Double {
        0.5 * rideableHeightMeters * rideableHeightMeters * periodSeconds
    }

    /// The wind's strength band. Direction stays separate in `windRelation`:
    /// 15 knots offshore and 15 knots onshore are the same band and opposite
    /// products, and collapsing them into one adjective loses the product.
    public var windStrength: WindStrength {
        WindStrength.strength(forKnots: windSpeedKnots)
    }

    public var windGustKnots: Double? {
        windGustMPS.map { Units.knots(fromMetersPerSecond: $0) }
    }

    /// Gust divided by mean — how *ragged* the wind is, rather than how strong.
    ///
    /// This is the number that separates a day people call "very windy" from
    /// one they call clean, even when the two share a mean speed: a 9-knot mean
    /// gusting to 16 shifts constantly and textures the face, and measured on
    /// this coast that ratio reaches 3x while the mean stays inside every
    /// "light wind" band the score has.
    ///
    /// 1.0 when the source reports no gust, which reads as perfectly steady and
    /// therefore costs nothing.
    public var gustRatio: Double {
        guard let gust = windGustMPS, windSpeedMPS > 0.5 else { return 1.0 }
        return max(1.0, gust / windSpeedMPS)
    }

    /// How much of the sea's energy is local wind chop rather than groundswell,
    /// 0...1, measured at the break.
    ///
    /// Energy goes as `H²`, so this is the ratio of the squares rather than of
    /// the heights. It is deliberately taken *after* the transform: long swell
    /// shoals up over the bar and short chop does not, so the share at the beach
    /// is markedly lower than the same hour offshore — at Bat Yam on 2026-08-29
    /// the open-sea shares were 18/28/37% where the beach saw 11/18/24%. A
    /// threshold set on the open-sea number would fire on the wrong hour.
    ///
    /// `nil` when the source did not separate the trains; see
    /// `swellHeightMeters`.
    public var windSeaEnergyShare: Double? {
        guard let swell = swellHeightMeters, let windSea = windSeaHeightMeters else { return nil }
        let total = swell * swell + windSea * windSea
        guard total > 0 else { return 0 }
        return (windSea * windSea) / total
    }

    public init(
        timestamp: Date,
        spotID: String,
        waveHeightMeters: Double,
        periodSeconds: Double,
        band: WaveBand,
        seaState: SeaState,
        windSpeedMPS: Double,
        windDirectionDegrees: Double,
        windRelation: WindRelation,
        openSeaHeightMeters: Double,
        isSynthetic: Bool,
        breakingLimitMeters: Double = 0,
        windGustMPS: Double? = nil,
        isDaylight: Bool = true,
        seaSurfaceTemperatureC: Double? = nil,
        airTemperatureC: Double? = nil,
        seaLevelMeters: Double? = nil,
        swellHeightMeters: Double? = nil,
        windSeaHeightMeters: Double? = nil,
        isCrossSea: Bool = false,
        longshoreCurrentMPS: Double? = nil,
        openSeaSwellHeightMeters: Double? = nil,
        openSeaSwellPeriodSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.spotID = spotID
        self.waveHeightMeters = waveHeightMeters
        self.periodSeconds = periodSeconds
        self.band = band
        self.seaState = seaState
        self.swellHeightMeters = swellHeightMeters
        self.windSeaHeightMeters = windSeaHeightMeters
        self.isCrossSea = isCrossSea
        self.longshoreCurrentMPS = longshoreCurrentMPS
        self.openSeaSwellHeightMeters = openSeaSwellHeightMeters
        self.openSeaSwellPeriodSeconds = openSeaSwellPeriodSeconds
        self.windSpeedMPS = windSpeedMPS
        self.windDirectionDegrees = windDirectionDegrees
        self.windRelation = windRelation
        self.openSeaHeightMeters = openSeaHeightMeters
        self.isSynthetic = isSynthetic
        self.breakingLimitMeters = breakingLimitMeters
        self.windGustMPS = windGustMPS
        self.isDaylight = isDaylight
        self.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        self.airTemperatureC = airTemperatureC
        self.seaLevelMeters = seaLevelMeters
    }
}
