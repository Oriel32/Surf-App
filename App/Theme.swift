import SwiftUI
import SurfCore

/// The aqua art direction from `design/screen-study.html`, as SwiftUI colours.
///
/// This file is the only place a semantic token becomes a pixel. `SurfCore`
/// emits `ColorToken` and never imports SwiftUI — the moment it does, the whole
/// build-and-test-off-a-Mac workflow dies — so the mapping lives here, once.
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
    static let choppy = Color(hex: 0xE866_3C)
    static let flat = Color(hex: 0x9AA7_AE)
    static let alert = Color(hex: 0xFF6B_4A)
    static let sand = Color(hex: 0xE8D9_BC)
}

/// Page, card and text colours for one appearance.
///
/// Declared explicitly rather than reaching for `UIColor.systemBackground`,
/// because the design study picks its own greys and because pulling UIKit into
/// the view layer for a colour is the sort of bridge claude.md rules out.
struct Theme {
    let page: Color
    let card: Color
    let text1: Color
    let text2: Color
    let rule: Color

    static let light = Theme(
        page: Color(hex: 0xF4FB_FC),
        card: Color(hex: 0xFFFF_FF),
        text1: Color(hex: 0x1014_18),
        text2: Color(hex: 0x7A88_91),
        rule: Color(hex: 0xE3EE_F1)
    )

    static let dark = Theme(
        page: Color(hex: 0x0B14_16),
        card: Color(hex: 0x101B_1E),
        text1: Color(hex: 0xE8F4_F6),
        text2: Color(hex: 0x94A9_AF),
        rule: Color(hex: 0x1E30_34)
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

/// Local beach time, formatted so a numeric run cannot reverse inside an RTL
/// paragraph.
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

    static func range(_ start: Date, _ end: Date) -> String {
        HebrewText.timeRange(hourMinute(start), hourMinute(end))
    }
}
