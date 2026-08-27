import Foundation

/// Every intermediate value the transformation passed through, for one hour at
/// one spot.
///
/// ## Why this exists
/// The height a surfer sees is a product of six independent factors — the
/// offshore model value, the spot's exposure coefficient, refraction, shoaling,
/// the depth-limited breaking cap and the Rayleigh set factor the slang band is
/// chosen from. When our answer disagrees with another forecast app, the final
/// number alone cannot say which factor is responsible, and tuning blind is how
/// a physics engine turns into a pile of fudge constants.
///
/// This is **developer diagnostics, not product vocabulary**: it is English,
/// unlocalised, and must never be rendered in a view. `Translator` is the only
/// thing allowed to speak to users.
public struct TransformTrace: Sendable, Equatable {
    /// Which partition of the sea a train came from.
    public enum TrainLabel: String, Sendable, Equatable {
        /// The groundswell partition — the train that makes a surfable wave.
        case swell
        /// Locally generated wind chop.
        case windWave = "wind wave"
        /// The unpartitioned combined sea, used when the source separates nothing.
        case combinedSea = "combined sea"
    }

    /// Why a train delivered nothing, when it delivered nothing.
    public enum Shadowing: String, Sendable, Equatable {
        /// Outside the spot's configured swell window — behind a mole or headland.
        case outsideSwellWindow = "outside the spot's swell window"
        /// Arriving from further than 90° off the shore-normal: from behind the beach.
        case behindTheShoreline = "arriving from behind the shoreline"
    }

    /// One wave train's journey from the open sea to the sandbar.
    ///
    /// The stage fields are filled in as the transformation proceeds and stay
    /// `nil` for stages a shadowed train never reached — an absent shoaling
    /// coefficient means the train was stopped before shoaling, which is a
    /// different statement from a coefficient of 1.
    public struct Train: Sendable, Equatable {
        public let label: TrainLabel
        public let openSeaHeightMeters: Double
        /// The period the physics actually used: Tp where the source gave one.
        public let periodSeconds: Double
        /// Whether `periodSeconds` is a true peak period. When false the source
        /// omitted Tp and the engine fell back to the mean — roughly a 22%
        /// under-read, and invisible in the final output without this flag.
        public let periodIsPeak: Bool
        public let meanPeriodSeconds: Double
        public let directionDegrees: Double
        /// Angle between the train's bearing and the shore-normal, 0 = straight in.
        public let incidentAngleDegrees: Double
        public let exposureCoefficient: Double

        public internal(set) var shadowing: Shadowing?
        public internal(set) var afterExposureMeters: Double?
        public internal(set) var refractionCoefficient: Double?
        public internal(set) var afterRefractionMeters: Double?
        public internal(set) var shoalingCoefficient: Double?
        /// Height at the break. Zero for a shadowed train.
        public internal(set) var heightMeters: Double = 0
    }

    public let spotID: String
    public let isSynthetic: Bool
    /// The spot's catalogued break depth, before tide.
    public let nominalDepthMeters: Double
    /// Sea level relative to MSL, as the model reported it. `nil` when absent.
    public let tideOffsetMeters: Double?
    /// The depth the physics actually used, floored at 0.5 m.
    public let depthMeters: Double
    public let trains: [Train]
    /// Quadrature sum of the trains, before the breaking cap.
    public let combinedMeters: Double
    public let breakingLimitMeters: Double
    /// Significant height at the break — the number the product displays.
    public let significantMeters: Double
    public let periodSeconds: Double
    public let dominantTrainLabel: TrainLabel?
    public let band: WaveBand

    /// Whether the sea exceeds what the bar can hold up. No longer clips the
    /// reported height — it tells the score the day is a closeout.
    public var capApplied: Bool {
        breakingLimitMeters > 0 && combinedMeters > breakingLimitMeters
    }

    /// The height the slang band was chosen from.
    public var bandDefiningMeters: Double {
        SurfRange(significantMeters: significantMeters).bandDefiningMeters
    }

    /// The top of the displayed range — the 1-in-10 set.
    public var setMeters: Double {
        SurfRange(significantMeters: significantMeters).setMeters
    }

    /// The whole chain as one factor: what the offshore value got multiplied by.
    /// `nil` when there was no offshore height to compare against.
    public func netFactor(openSeaHeightMeters: Double) -> Double? {
        guard openSeaHeightMeters > 0.001 else { return nil }
        return significantMeters / openSeaHeightMeters
    }
}

// MARK: - Report

public extension TransformTrace {
    /// The trace as plain lines, for the smoke tool and the calibration ledger.
    ///
    /// Developer diagnostics. Never render this in the app.
    func report() -> [String] {
        var lines: [String] = []

        func metres(_ value: Double) -> String { String(format: "%.2f m", value) }
        func factor(_ value: Double) -> String { String(format: "%.3f", value) }

        if isSynthetic {
            lines.append("SYNTHETIC (Gulf of Eilat) — derived from wind, no model swell")
        }

        for (index, train) in trains.enumerated() {
            let periodKind = train.periodIsPeak ? "Tp" : "Tm"
            lines.append(
                "TRAIN \(index + 1) (\(train.label.rawValue))"
                    + "  \(metres(train.openSeaHeightMeters))"
                    + "  \(periodKind) \(String(format: "%.1f", train.periodSeconds)) s"
                    + "  from \(Int(train.directionDegrees.rounded()))°"
            )
            if !train.periodIsPeak {
                lines.append("    ⚠ no peak period from the source — using the mean, which under-reads")
            }
            lines.append("    incident angle    \(String(format: "%.0f", train.incidentAngleDegrees))°")

            if let shadowing = train.shadowing {
                lines.append("    SHADOWED — \(shadowing.rawValue) → 0.00 m")
                continue
            }
            if let exposed = train.afterExposureMeters {
                lines.append("    × exposure   \(factor(train.exposureCoefficient))  → \(metres(exposed))")
            }
            if let refraction = train.refractionCoefficient, let after = train.afterRefractionMeters {
                lines.append("    × refraction \(factor(refraction))  → \(metres(after))")
            }
            if let shoaling = train.shoalingCoefficient {
                lines.append("    × shoaling   \(factor(shoaling))  → \(metres(train.heightMeters))")
            }
        }

        if trains.count > 1 {
            let squares = trains
                .map { String(format: "%.2f²", $0.heightMeters) }
                .joined(separator: " + ")
            lines.append("COMBINED   √(\(squares)) = \(metres(combinedMeters))")
        }

        let tide = tideOffsetMeters.map { String(format: " %+.2f m tide", $0) } ?? " (no tide data)"
        lines.append(
            "DEPTH      \(metres(nominalDepthMeters)) nominal\(tide) = \(metres(depthMeters))"
        )
        lines.append(
            "BREAK CAP  0.78 × \(metres(depthMeters)) = \(metres(breakingLimitMeters))"
                + (capApplied
                    ? "   ← EXCEEDED: the bar cannot hold this. Score is scored on \(metres(breakingLimitMeters)), the height is reported as measured."
                    : "   not reached")
        )

        let dominant = dominantTrainLabel.map { " (from the \($0.rawValue) — the tallest train)" } ?? ""
        lines.append("PERIOD     \(String(format: "%.1f", periodSeconds)) s\(dominant)")
        lines.append(
            "DISPLAYED  \(metres(significantMeters))–\(metres(setMeters))"
                + "   ← significant through to the 1-in-10 sets"
        )
        lines.append("BAND       \(band.hebrew) / \(band.english)   ← chosen from \(metres(bandDefiningMeters))")
        if !band.isBreakingSurf {
            lines.append(
                "           below the break point — needs "
                    + metres(SurfBreaking.minimumHeightMeters(periodSeconds: periodSeconds))
                    + " at \(String(format: "%.1f", periodSeconds)) s"
            )
        }

        return lines
    }
}

// MARK: - Labelling

extension RawMarineSample {
    /// Which partition a train came from, for the trace.
    func label(for train: SwellComponent) -> TransformTrace.TrainLabel {
        if train == primarySwell { return .swell }
        if train == windWave { return .windWave }
        return .combinedSea
    }
}
