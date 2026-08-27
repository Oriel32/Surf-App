import Foundation

/// Deep water to the sandbar: the physics that separates this app from a
/// weather widget.
///
/// Models report significant wave height 10–25 km offshore in water deeper than
/// 50 m, at roughly 9 km resolution. Between there and the beach the wave
/// shoals, refracts, is sheltered by whatever the coastline puts in its way, and
/// finally breaks. Every one of those steps changes the number, and reporting
/// the offshore value as "the wave at the beach" is the failure mode that kills
/// trust in a surf forecast.
///
/// All functions here are pure, `nonisolated`, and free of dependencies, so the
/// whole engine is testable without a network or a clock.
public enum WaveTransform {
    /// Standard gravity, m/s².
    public static let g = 9.806_65

    /// Beyond this the hyperbolic terms saturate and the deep-water limits apply
    /// exactly; evaluating `sinh` past it overflows.
    private static let deepWaterKD = 10.0

    // MARK: - Linear wave theory

    /// Solves the linear dispersion relation `ω² = g·k·tanh(k·d)` for the wave
    /// number `k`, by Newton–Raphson from the deep-water guess.
    ///
    /// Converges in a handful of iterations across every depth this app sees.
    public static func waveNumber(periodSeconds period: Double, depthMeters depth: Double) -> Double {
        guard period > 0, depth > 0 else { return 0 }
        let omega = 2 * Double.pi / period
        let omegaSquared = omega * omega
        var k = omegaSquared / g  // deep-water first guess

        for _ in 0..<30 {
            let kd = k * depth
            guard kd < deepWaterKD else { break }  // already at the deep-water limit
            let tanhKD = tanh(kd)
            let f = g * k * tanhKD - omegaSquared
            let derivative = g * tanhKD + g * kd * (1 - tanhKD * tanhKD)
            guard derivative != 0 else { break }
            let delta = f / derivative
            k -= delta
            if abs(delta) < 1e-12 { break }
        }
        return k
    }

    /// Ratio `n = Cg / C`. Tends to 1/2 in deep water and 1 in shallow water.
    private static func groupVelocityRatio(waveNumber k: Double, depthMeters depth: Double) -> Double {
        let kd = k * depth
        guard kd < deepWaterKD else { return 0.5 }
        let twoKD = 2 * kd
        return 0.5 * (1 + twoKD / sinh(twoKD))
    }

    /// Shoaling coefficient `Ks = sqrt(Cg₀ / Cg)`.
    ///
    /// As the wave feels the bottom its group velocity drops; energy flux is
    /// conserved, so the height rises. This is why a 1 m offshore swell can
    /// stand up taller than 1 m before it breaks.
    public static func shoalingCoefficient(periodSeconds period: Double, depthMeters depth: Double) -> Double {
        guard period > 0, depth > 0 else { return 1 }
        let k = waveNumber(periodSeconds: period, depthMeters: depth)
        guard k > 0 else { return 1 }
        let celerity = (2 * Double.pi / period) / k
        let groupVelocity = groupVelocityRatio(waveNumber: k, depthMeters: depth) * celerity
        let deepGroupVelocity = g * period / (4 * Double.pi)
        guard groupVelocity > 0 else { return 1 }
        return (deepGroupVelocity / groupVelocity).squareRoot()
    }

    /// Refraction coefficient `Kr = sqrt(cos θ₀ / cos θ)` with θ from Snell's law.
    ///
    /// A wave arriving at an angle bends towards the shore-normal as it slows,
    /// spreading its energy along a wider stretch of beach — so an oblique swell
    /// delivers less height than the same swell arriving straight on.
    ///
    /// - Parameter incidentAngleDegrees: angle between the deep-water wave
    ///   direction and the shore-normal, 0 = straight in.
    /// - Returns: `nil` when the swell arrives from behind the shoreline and
    ///   cannot reach this beach at all.
    public static func refractionCoefficient(
        periodSeconds period: Double,
        depthMeters depth: Double,
        incidentAngleDegrees incidentAngle: Double
    ) -> Double? {
        let theta0 = abs(incidentAngle) * .pi / 180
        guard theta0 < .pi / 2 else { return nil }  // shoreline is in shadow

        let k = waveNumber(periodSeconds: period, depthMeters: depth)
        guard k > 0 else { return 1 }
        let celerity = (2 * Double.pi / period) / k
        let deepCelerity = g * period / (2 * Double.pi)
        guard deepCelerity > 0 else { return 1 }

        let sinTheta = min(1, (celerity / deepCelerity) * sin(theta0))
        let cosTheta = max(1e-6, (1 - sinTheta * sinTheta).squareRoot())
        return (cos(theta0) / cosTheta).squareRoot()
    }

    /// Depth-limited breaking: a wave cannot stand taller than `0.78 × depth`
    /// before it collapses forward. This is the cap that keeps a big offshore
    /// storm from being reported as an impossible 4 m face on a 2 m sandbar.
    public static func breakingHeightLimit(depthMeters depth: Double) -> Double {
        0.78 * depth
    }

    // MARK: - Full transformation

    /// Turns one hour of open-sea model output into what breaks at one spot.
    public static func transform(_ sample: RawMarineSample, at spot: Spot) -> SpotConditions {
        switch spot.basin {
        case .gulfOfEilat:
            return synthesiseGulfOfEilat(sample, at: spot)
        case .mediterranean:
            return transformMediterranean(sample, at: spot)
        }
    }

    /// One transformed wave train at the break.
    private struct BrokenTrain {
        let heightMeters: Double
        let periodSeconds: Double
    }

    private static func transformMediterranean(_ sample: RawMarineSample, at spot: Spot) -> SpotConditions {
        // The tide moves the bar the wave breaks on. The Mediterranean range is
        // only a few dozen centimetres, but the breaking cap is `0.78 x depth`,
        // so on a 1.5 m bar even 0.2 m of tide moves the ceiling by 10 percent -
        // and it is free, because the model already sends sea level.
        //
        // Floored well above zero: a bad model value must not produce a
        // negative depth and a nonsense wave.
        let depth = max(0.5, spot.breakDepthMeters + (sample.seaLevelMeters ?? 0))

        // Every train on its own geometry. Taking the height from the combined
        // sea while taking the period and bearing from the swell partition -
        // which is what this did before - applies groundswell physics to a
        // height that wind chop inflated.
        let trains = sample.partitions.map { transform($0, at: spot, depthMeters: depth) }

        // Independent trains add in ENERGY, so heights add in quadrature. Adding
        // them linearly would double-count a sea that is mostly one train.
        let combined = trains.reduce(0) { $0 + $1.heightMeters * $1.heightMeters }.squareRoot()

        // The cap is depth-limited breaking, so it applies to the whole sea at
        // the break, not to each train separately.
        let height = min(combined, breakingHeightLimit(depthMeters: depth))

        // The period reported is the dominant train's, never a blend: averaging
        // a 9 s groundswell with a 3 s chop describes neither of them.
        let dominant = trains.max { $0.heightMeters < $1.heightMeters }

        return assemble(
            sample: sample,
            spot: spot,
            heightMeters: height,
            periodSeconds: dominant?.periodSeconds ?? 0,
            isSynthetic: false
        )
    }

    /// Shelter, shoal and refract a single train. Returns zero height when the
    /// train arrives from behind the shoreline and cannot reach the beach.
    private static func transform(
        _ train: SwellComponent,
        at spot: Spot,
        depthMeters depth: Double
    ) -> BrokenTrain {
        // Peak period throughout: shoaling and refraction are both functions of
        // wavelength, and the wavelength that matters is the energetic one.
        let period = train.surfPeriodSeconds

        // A sector the break simply cannot see - behind a mole or a headland -
        // is shadowed, not merely reduced. The exposure coefficient is a scalar
        // and cannot express "from that direction, nothing arrives".
        if let window = spot.swellWindow, !window.admits(train.directionDegrees) {
            return BrokenTrain(heightMeters: 0, periodSeconds: period)
        }

        // Sheltering first: breakwaters, headlands and piers block incident
        // energy offshore, before the wave ever reaches the shoaling zone.
        // (The prose spec lists the coefficient last; applying it after the
        // breaking cap would reduce an already-capped height twice.)
        let incidentHeight = train.heightMeters * spot.exposureCoefficient

        let incidentAngle = Compass.angularDistance(
            train.directionDegrees,
            spot.shorelineNormalDegrees
        )

        guard let refraction = refractionCoefficient(
            periodSeconds: period,
            depthMeters: depth,
            incidentAngleDegrees: incidentAngle
        ) else {
            return BrokenTrain(heightMeters: 0, periodSeconds: period)
        }

        let shoaling = shoalingCoefficient(periodSeconds: period, depthMeters: depth)
        return BrokenTrain(
            heightMeters: incidentHeight * shoaling * refraction,
            periodSeconds: period
        )
    }

    /// The Gulf of Eilat receives no swell — it is a closed, narrow basin that
    /// global wave models do not resolve, so their output there is noise. Wave
    /// height is derived directly from the local wind instead, and the UI must
    /// label the result as locally derived rather than modelled.
    private static func synthesiseGulfOfEilat(_ sample: RawMarineSample, at spot: Spot) -> SpotConditions {
        let windKnots = Units.knots(fromMetersPerSecond: sample.windSpeedMPS)
        let height = windKnots * 0.04
        let period = 3 + 0.15 * windKnots

        return assemble(
            sample: sample,
            spot: spot,
            heightMeters: min(height, breakingHeightLimit(depthMeters: spot.breakDepthMeters)),
            periodSeconds: period,
            isSynthetic: true
        )
    }

    private static func assemble(
        sample: RawMarineSample,
        spot: Spot,
        heightMeters: Double,
        periodSeconds: Double,
        isSynthetic: Bool
    ) -> SpotConditions {
        let relation = Compass.windRelation(
            windFromDegrees: sample.windDirectionDegrees,
            shorelineNormalDegrees: spot.shorelineNormalDegrees
        )
        return SpotConditions(
            timestamp: sample.timestamp,
            spotID: spot.id,
            waveHeightMeters: heightMeters,
            periodSeconds: periodSeconds,
            // Chosen from the sets rather than the significant height: nobody
            // names a beach day after its statistical mean. See SurfRange.
            band: WaveBand.band(
                forHeightMeters: SurfRange(significantMeters: heightMeters).bandDefiningMeters
            ),
            seaState: SeaStateClassifier.classify(
                heightMeters: heightMeters,
                windSpeedMPS: sample.windSpeedMPS,
                relation: relation
            ),
            windSpeedMPS: sample.windSpeedMPS,
            windDirectionDegrees: sample.windDirectionDegrees,
            windRelation: relation,
            openSeaHeightMeters: sample.waveHeightMeters,
            isSynthetic: isSynthetic,
            windGustMPS: sample.windGustMPS,
            isDaylight: sample.isDaylight,
            seaSurfaceTemperatureC: sample.seaSurfaceTemperatureC,
            airTemperatureC: sample.airTemperatureC,
            seaLevelMeters: sample.seaLevelMeters
        )
    }
}

/// Wind against water surface — the texture layer.
public enum SeaStateClassifier {
    /// - Parameter rules: the thresholds, injected so each edge can be moved and
    ///   tested on its own rather than being a literal buried in a conditional.
    public static func classify(
        heightMeters: Double,
        windSpeedMPS: Double,
        relation: WindRelation,
        rules: SeaStateRules = .standard
    ) -> SeaState {
        guard heightMeters >= rules.flatCeilingMeters else { return .flat }

        let knots = Units.knots(fromMetersPerSecond: windSpeedMPS)

        // Glass needs either almost no wind at all, or a wind coming off the
        // land that grooms the face instead of tearing it.
        if knots < rules.glassyCalmKnots
            || (relation.isFavourableForShape && knots < rules.groomedOffshoreCeilingKnots) {
            return .glassy
        }

        // Onshore wind past roughly 12 knots tears the surface and breaks waves
        // before they can form.
        if (relation == .onshore || relation == .crossOnshore) && knots >= rules.onshoreChopKnots {
            return .choppy
        }

        return knots >= rules.universalChopKnots ? .choppy : .fair
    }
}
