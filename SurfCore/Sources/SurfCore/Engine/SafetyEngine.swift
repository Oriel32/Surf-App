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

    private static func offshoreDriftAlert(
        _ conditions: SpotConditions,
        profile: UserProfile
    ) -> SafetyAlert? {
        guard conditions.windRelation.blowsAwayFromShore else { return nil }

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

        let knots = conditions.windSpeedKnots
        guard knots >= threshold else { return nil }

        let severity: AlertSeverity =
            (onFloatingCraft || profile.skill == .beginner || knots >= 15) ? .danger : .caution

        return SafetyAlert(
            kind: .offshoreDrift,
            severity: severity,
            hebrewTitle: "רוח מהיבשה – סכנת סחיפה לים",
            hebrewBody: """
            הים נראה שטוח ורגוע מהחוף, אבל זו אשליה: מעבר לצל הרוח של הבניינים והמצוק \
            הרוח מכה בעוצמה של \(Int(knots.rounded())) קשר ודוחפת אל הים הפתוח, מהר יותר \
            ממה שאפשר לחתור בחזרה. מתחילים, גולשי סאפ וקיאקים – אין להיכנס למים.
            """
        )
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
