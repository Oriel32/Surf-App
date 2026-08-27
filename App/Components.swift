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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // The score is the one number allowed to move: it counts
                    // rather than cutting when the sport or the hour changes,
                    // and its band colour crossfades with it. The wave data
                    // beside it stays still, by policy.
                    .contentTransition(.numericText(value: Double(hour.score.value)))
                    .animation(Motion.arrival(reduceMotion), value: hour.score.value)
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

/// A placeholder in the shape of the thing that is coming.
///
/// `Aqua.sand` is the art direction's skeleton colour and was already being used
/// for this by hand in `SpotRow`; this is that, extracted so every screen fakes
/// its layout the same way.
/// The shimmer lives here rather than in a general-purpose modifier because the
/// shape is only known here. Applied to a whole screen, a sweep lights up the
/// gaps between the cards as well as the cards.
@MainActor
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12
    let theme: Theme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Travelling `UnitPoint`s rather than a measured offset: they are
    /// animatable and scale-free, so the sweep crosses the block correctly
    /// without a `GeometryReader` to tell it how wide the block is.
    @State private var sweepStart = UnitPoint(x: -1.2, y: 0.5)
    @State private var sweepEnd = UnitPoint(x: -0.2, y: 0.5)

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(height / 2, 14), style: .continuous)
    }

    var body: some View {
        shape
            .fill(Aqua.sand.opacity(theme.isDark ? 0.22 : 0.45))
            .overlay {
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.30), .clear],
                        startPoint: sweepStart,
                        endPoint: sweepEnd
                    )
                    .blendMode(.plusLighter)
                }
            }
            .clipShape(shape)
            .frame(width: width, height: height)
            .onAppear {
                // Reduce Motion leaves the static sand tint, which is a
                // complete loading state on its own rather than a degraded one.
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    sweepStart = UnitPoint(x: 1.2, y: 0.5)
                    sweepEnd = UnitPoint(x: 2.2, y: 0.5)
                }
            }
            .accessibilityHidden(true)
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
