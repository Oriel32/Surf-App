import SwiftUI
import SurfCore

/// The aqua art direction from `app_ui.md`, as SwiftUI.
///
/// This file is the only place a semantic token becomes a pixel. `SurfCore`
/// emits `ColorToken` and never imports SwiftUI — the moment it does, the whole
/// build-and-test-off-a-Mac workflow dies.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Aqua {
    static let aqua400 = Color(hex: 0x5BDD_E1)
    static let aqua500 = Color(hex: 0x34CF_D5)
    static let aqua600 = Color(hex: 0x1FB2_B8)
    static let mist = Color(hex: 0xEAF9_FB)
    static let blush = Color(hex: 0xF7ED_F6)
    static let sand = Color(hex: 0xE8D9_BC)
    static let choppy = Color(hex: 0xE866_3C)
    static let flat = Color(hex: 0x9AA7_AE)
    static let alert = Color(hex: 0xFF6B_4A)
}

/// Page, card and text colours for one appearance.
///
/// Declared explicitly rather than reaching for `UIColor.systemBackground`,
/// because the art direction picks its own neutrals and because pulling UIKit
/// into the view layer for a colour is the sort of bridge claude.md rules out.
struct Theme {
    let page: Color
    let card: Color
    let tinted: Color
    let text1: Color
    let text2: Color
    let hairline: Color
    let isDark: Bool

    static let light = Theme(
        page: Color(hex: 0xF4FB_FC),
        card: Color(hex: 0xFFFF_FF),
        tinted: Aqua.mist,
        text1: Color(hex: 0x1014_18),
        text2: Color(hex: 0x7A88_91),
        hairline: Color(hex: 0xF2F6_F8),
        isDark: false
    )

    static let dark = Theme(
        page: Color(hex: 0x0B14_16),
        card: Color(hex: 0x101B_1E),
        tinted: Color(hex: 0x1629_2D),
        text1: Color(hex: 0xE8F4_F6),
        text2: Color(hex: 0x94A9_AF),
        hairline: Color(hex: 0x1E30_34),
        isDark: true
    )

    static func current(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? dark : light
    }
}

extension ColorToken {
    /// Colour reinforces, it never carries: every view using this also renders
    /// the word or glyph that goes with it, so nothing is lost in greyscale.
    var color: Color {
        switch self {
        case .neutral: return Aqua.flat
        case .hero: return Aqua.aqua500
        case .positive: return Aqua.aqua600
        case .caution: return Aqua.choppy
        case .danger: return Aqua.alert
        }
    }
}

// MARK: - Shape and elevation

enum Metric {
    /// app_ui.md: cards 28, photographs inset 22, pill buttons 56 tall,
    /// icon chips 14, utility circles 36–44.
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    static let pillHeight: CGFloat = 56
    static let tapTarget: CGFloat = 44
}

extension View {
    /// A card surface. No visible border — the art direction allows only a
    /// hairline where two white surfaces stack, and the elevation comes from a
    /// wide, nearly invisible shadow rather than a dark tight one.
    func surfCard(_ theme: Theme, radius: CGFloat = Metric.cardRadius) -> some View {
        background(theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: Color(hex: 0x102C_34).opacity(theme.isDark ? 0.30 : 0.08),
                radius: 16, x: 0, y: 12
            )
    }

    func surfButtonShadow(_ theme: Theme) -> some View {
        shadow(
            color: Color(hex: 0x102C_34).opacity(theme.isDark ? 0.24 : 0.05),
            radius: 4, x: 0, y: 2
        )
    }

    /// Every tappable row meets the 44pt minimum.
    func tappableRow() -> some View {
        frame(minHeight: Metric.tapTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Type

/// `app_ui.md` asks for a geometric sans with rounded terminals. The named
/// candidates — Poppins, Outfit, Satoshi, General Sans — carry **no Hebrew
/// glyphs**, and Hebrew is this app's primary locale, so none of them can set
/// the product's actual vocabulary.
///
/// SF Pro Rounded is the system's answer to that brief: rounded terminals,
/// full Hebrew coverage, and it arrives with Dynamic Type, optical sizing and
/// tracking tables already correct. Everything below is a text style, never a
/// hardcoded point size, so all twelve Dynamic Type sizes work by default.
enum SurfFont {
    static let score = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let headline = Font.system(.title2, design: .rounded, weight: .semibold)
    /// The light half of the mixed-weight headline: app_ui.md calls the pairing
    /// a signature, where the light line states the promise and the bold line
    /// states the payoff.
    static let headlineLight = Font.system(.title2, design: .rounded, weight: .light)
    static let cardTitle = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let body = Font.system(.body, design: .rounded)
    static let meta = Font.system(.footnote, design: .rounded)
    static let label = Font.system(.caption, design: .rounded, weight: .medium)
    /// Digits that line up in a column.
    static let tabular = Font.system(.subheadline, design: .rounded, weight: .semibold)
        .monospacedDigit()
}

/// Local beach time, formatted so a numeric run cannot reverse inside RTL text.
enum ClockText {
    static func hourMinute(_ date: Date) -> String {
        // Built per call rather than held as a static: `DateFormatter` is a
        // non-Sendable class, and a shared one is the data race Swift 6 rejects.
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// A window that runs to the end of the day ends at the next midnight, and
    /// formatting that as `00:00` makes an all-day window read as though it
    /// runs backwards — the same class of bug claude.md records for
    /// `bestWindowToday`. Render the closing midnight as 24:00 instead.
    static func range(_ start: Date, _ end: Date) -> String {
        let closing = hourMinute(end)
        let shown = (closing == "00:00" && end > start) ? "24:00" : closing
        return HebrewText.timeRange(hourMinute(start), shown)
    }

    /// Short weekday, for a chart axis where the full name will not fit.
    static func weekdayShortHebrew(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    static func weekdayHebrew(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func dayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d/M"
        return HebrewText.ltr(formatter.string(from: date))
    }
}
