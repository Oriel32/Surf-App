import SwiftUI
import SurfCore

/// The offshore-drift warning. Full width, above everything, no dismiss control.
///
/// There is deliberately no way to close this. A glassy offshore morning scores
/// well for an experienced surfer and is genuinely life-threatening for a
/// beginner at the same time; both facts have to land, and the banner wins the
/// hierarchy whenever both are on screen.
@MainActor
struct SafetyBanner: View {
    let alert: SafetyAlert
    let theme: Theme

    private var accent: Color { alert.severity.colorToken.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(alert.hebrewTitle)
                    .font(SurfFont.cardTitle)
            }
            Text(alert.hebrewBody)
                .font(SurfFont.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            accent.opacity(theme.isDark ? 0.18 : 0.12),
            in: RoundedRectangle(cornerRadius: Metric.innerRadius, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(alert.hebrewTitle). \(alert.hebrewBody)")
        // Announced before anything else on the screen.
        .accessibilitySortPriority(100)
    }
}

/// Layer 1: the whole decision, in one card.
///
/// Every string comes from `Translator`, so the rule that height is never shown
/// without its slang is enforced in the engine rather than re-litigated here.
@MainActor
struct HeroSection: View {
    let hour: HourlyForecast
    let heightUnit: HeightUnit
    let theme: Theme

    @Environment(\.dynamicTypeSize) private var typeSize

    private var presentation: ConditionsPresentation {
        Translator.present(hour, heightUnit: heightUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // At accessibility sizes the score and its band stop sitting side
            // by side and stack instead, so the card reflows rather than
            // truncating. claude.md requires this to hold at AX5.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))

            layout {
                Text(presentation.scoreText ?? "—")
                    .font(SurfFont.score)
                    .foregroundStyle(presentation.scoreToken?.color ?? theme.text2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.scoreBand?.hebrew ?? "")
                        .font(SurfFont.cardTitle)
                        .foregroundStyle(theme.text1)
                    Text(hour.score.sport.hebrew)
                        .font(SurfFont.meta)
                        .foregroundStyle(theme.text2)
                }
            }

            // Metric and slang together, always. Never the number alone.
            Text(presentation.waveLine)
                .font(SurfFont.headline)
                .foregroundStyle(theme.text1)
                .fixedSize(horizontal: false, vertical: true)

            WrappingRow {
                SeaStateChip(word: presentation.seaStateHebrew, token: presentation.seaStateToken)
                WindReadout(presentation: presentation, hour: hour, theme: theme)
            }

            if let notice = presentation.derivationNoticeHebrew {
                Label(notice, systemImage: "info.circle")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .surfCard(theme)
        // VoiceOver reads one coherent sentence, not six fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// Lays children in a row that wraps instead of clipping when type grows.
@MainActor
struct WrappingRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout { content }
    }
}

/// The word is always present; the colour only reinforces it.
@MainActor
struct SeaStateChip: View {
    let word: String
    let token: ColorToken

    var body: some View {
        Text(word)
            .font(SurfFont.label)
            .foregroundStyle(token.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(token.color.opacity(0.14), in: Capsule())
    }
}

@MainActor
struct WindReadout: View {
    let presentation: ConditionsPresentation
    let hour: HourlyForecast
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            WindArrow(blowingFromDegrees: hour.conditions.windDirectionDegrees)
                .foregroundStyle(theme.text2)
            // The relation word outranks the arrow and the number: "offshore"
            // is the fact that changes what the user does.
            Text(presentation.windRelationHebrew)
                .font(SurfFont.label)
                .foregroundStyle(theme.text1)
            Text(HebrewText.knots(hour.conditions.windSpeedKnots))
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
        }
    }
}

/// Points the way the wind is blowing, in real-world geography.
///
/// Pinned against RTL mirroring. Under a right-to-left layout every glyph flips
/// by default, and a mirrored compass arrow would tell a surfer the wind is
/// offshore when it is onshore.
@MainActor
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
