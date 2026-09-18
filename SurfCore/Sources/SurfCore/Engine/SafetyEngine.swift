import Foundation

/// Hazard detection. Evaluated before the score, and outranking it everywhere.
///
/// The offshore-drift case is the one this app exists to get right. From the
/// sand an offshore morning looks flat, quiet and inviting, because the wind is
/// behind the viewer and the water's surface is smooth. A few dozen metres out,
/// past the wind shadow of the buildings and the cliff, it hits hard and pushes
/// steadily out to sea — and a beginner on a board cannot paddle back against
/// it. The sea looking calm is precisely the symptom.
public enum SafetyEngine {
    public static func alerts(for conditions: SpotConditions, profile: UserProfile) -> [SafetyAlert] {
        var result: [SafetyAlert] = []
        if let drift = offshoreDriftAlert(conditions, profile: profile) {
            result.append(drift)
        }
        if let surf = largeSurfAlert(conditions, profile: profile) {
            result.append(surf)
        }
        return result
    }

    /// Two independent witnesses, and either one is enough.
    ///
    /// The model is a 9 km grid cell averaged over an hour; the station is a mast
    /// on this coast ten minutes ago. Each can miss an offshore morning the other
    /// sees, so the alert fires on whichever says the wind is blowing out to sea,
    /// and quotes the stronger of the two.
    ///
    /// **A measurement can raise this alert and can never cancel it.** A station
    /// is not the water at the break: it sits behind the same buildings that
    /// create the illusion this alert exists to describe, so a calm reading is
    /// not evidence of a calm sea. Letting one suppress a modelled hazard would
    /// turn the one screen that must over-warn into one that argues with itself.
    private static func offshoreDriftAlert(
        _ conditions: SpotConditions,
        profile: UserProfile
    ) -> SafetyAlert? {
        // Anyone on a floating craft is at far greater risk than a surfer on a
        // short board: a SUP is a sail, and it cannot be duck-dived under a gust.
        // Skill at *surfing* does not change that, so a paddler is always held to
        // the most cautious threshold — an advanced surfer on a SUP in a 9-knot
        // offshore is still being carried out to sea.
        let onFloatingCraft = profile.sport == .sup
        let threshold = onFloatingCraft
            ? min(profile.skill.offshoreWarningThresholdKnots,
                  SkillLevel.beginner.offshoreWarningThresholdKnots)
            : profile.skill.offshoreWarningThresholdKnots

        let modelKnots = conditions.windRelation.blowsAwayFromShore
            ? conditions.windSpeedKnots
            : nil
        let measured = conditions.measuredWind.flatMap {
            $0.relation.blowsAwayFromShore ? $0 : nil
        }
        let measuredKnots = measured?.speedKnots

        let triggering = [modelKnots, measuredKnots].compactMap { $0 }.filter { $0 >= threshold }
        guard let knots = triggering.max() else { return nil }

        let severity: AlertSeverity =
            (onFloatingCraft || profile.skill == .beginner || knots >= 15) ? .danger : .caution

        // Named only when the station is the reason this fired, or the stronger
        // of the two — otherwise the measurement is corroboration and saying so
        // just lengthens a banner that has to be read at a glance.
        let attribution = measured.flatMap { wind -> String? in
            guard wind.speedKnots >= threshold,
                  wind.speedKnots >= (modelKnots ?? 0) else { return nil }
            return " נמדדו \(HebrewText.ltr("\(Int(wind.speedKnots.rounded()))")) קשר "
                + "בתחנת \(wind.stationNameHebrew) ב-\(HebrewText.ltr(clockTime(wind.observedAt)))."
        } ?? ""

        return SafetyAlert(
            kind: .offshoreDrift,
            severity: severity,
            hebrewTitle: "רוח מהיבשה – סכנת סחיפה לים",
            hebrewBody: """
            הים נראה שטוח ורגוע מהחוף, אבל זו אשליה: מעבר לצל הרוח של הבניינים והמצוק \
            הרוח מכה בעוצמה של \(Int(knots.rounded())) קשר ודוחפת אל הים הפתוח, מהר יותר \
            ממה שאפשר לחתור בחזרה.\(attribution) מתחילים, גולשי סאפ וקיאקים – אין להיכנס למים.
            """
        )
    }

    /// The measurement's own clock time in beach time, not its age.
    ///
    /// A forecast is cached for up to half an hour, so "לפני 10 דקות" baked into
    /// the text at build time is a claim that quietly stops being true. `09:40`
    /// stays correct however long the banner is on screen.
    private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let zone = TimeZone(identifier: "Asia/Jerusalem") { formatter.timeZone = zone }
        return formatter.string(from: date)
    }

    private static func largeSurfAlert(
        _ conditions: SpotConditions,
        profile: UserProfile
    ) -> SafetyAlert? {
        let band = conditions.band

        // Compared in metres, against the measured height, rather than by
        // comparing band cases: the band table is product vocabulary and gets
        // re-cut when the vocabulary is wrong, and that must not be able to
        // move a safety trigger. See SkillLevel.largeSurfWarningThresholdMeters.
        guard conditions.waveHeightMeters >= profile.skill.largeSurfWarningThresholdMeters else {
            return nil
        }

        let severity: AlertSeverity = band == .doubleHead ? .danger : .caution
        return SafetyAlert(
            kind: .largeSurf,
            severity: severity,
            hebrewTitle: "גלים גבוהים – \(band.hebrew)",
            hebrewBody: """
            גובה הגלים בחוף הוא כ-\(String(format: "%.1f", conditions.waveHeightMeters)) מ׳ \
            (\(band.hebrew)). בתנאים כאלה יש זרמי חתירה חזקים והכניסה למים מתאימה \
            לגולשים מנוסים בלבד.
            """
        )
    }
}
