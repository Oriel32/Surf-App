import SwiftUI
import SurfCore

/// The offshore-drift warning. Full width, above everything, no dismiss control.
///
/// There is deliberately no way to close this. A glassy offshore morning scores
/// well for an experienced surfer and is genuinely life-threatening for a
/// beginner at the same time; both facts have to land, and the banner wins the
/// hierarchy whenever both are on screen.
struct SafetyBanner: View {
    let alert: SafetyAlert

    private var accent: Color { alert.severity.colorToken.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(alert.hebrewTitle)
                    .font(.headline)
            }
            Text(alert.hebrewBody)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(accent, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(alert.hebrewTitle). \(alert.hebrewBody)")
        // Announced before anything else on the screen.
        .accessibilitySortPriority(100)
    }
}

/// Layer 1: the whole decision, in one card.
///
/// Every string here comes from `Translator`, so the rule that height is never
/// shown without its slang is enforced in the engine and not re-litigated in
/// the view.
struct HeroSection: View {
    let hour: HourlyForecast
    let theme: Theme

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 64

    private var presentation: ConditionsPresentation {
        Translator.present(hour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.scoreText ?? "—")
                    .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                    .foregroundStyle(presentation.scoreToken?.color ?? theme.text2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.scoreBand?.hebrew ?? "")
                        .font(.headline)
                        .foregroundStyle(theme.text1)
                    Text(hour.score.sport.hebrew)
                        .font(.subheadline)
                        .foregroundStyle(theme.text2)
                }
            }

            // Metric and slang together, always. Never the number alone.
            Text(presentation.waveLine)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text1)

            HStack(spacing: 10) {
                SeaStateChip(
                    word: presentation.seaStateHebrew,
                    token: presentation.seaStateToken
                )
                WindReadout(presentation: presentation, hour: hour, theme: theme)
            }

            if let notice = presentation.derivationNoticeHebrew {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 20))
        // VoiceOver reads one coherent sentence, not six fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// The word is always present; the colour only reinforces it.
struct SeaStateChip: View {
    let word: String
    let token: ColorToken

    var body: some View {
        Text(word)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(token.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(token.color.opacity(0.14), in: Capsule())
    }
}

struct WindReadout: View {
    let presentation: ConditionsPresentation
    let hour: HourlyForecast
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            WindArrow(blowingFromDegrees: hour.conditions.windDirectionDegrees)
                .foregroundStyle(theme.text2)
            // The relation word outranks the arrow and the number: "offshore"
            // is the fact that changes what the user does.
            Text(presentation.windRelationHebrew)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text1)
            Text(HebrewText.knots(hour.conditions.windSpeedKnots))
                .font(.subheadline)
                .foregroundStyle(theme.text2)
        }
    }
}

/// Points the way the wind is blowing, in real-world geography.
///
/// Pinned against RTL mirroring. Under a right-to-left layout every glyph
/// flips by default, and a mirrored compass arrow would tell a surfer the wind
/// is offshore when it is onshore.
struct WindArrow: View {
    /// Degrees true the wind blows *from*.
    let blowingFromDegrees: Double

    var body: some View {
        Image(systemName: "arrow.up")
            .flipsForRightToLeftLayoutDirection(false)
            .rotationEffect(.degrees(blowingFromDegrees + 180))
            // The word beside it carries the meaning for VoiceOver.
            .accessibilityHidden(true)
    }
}
