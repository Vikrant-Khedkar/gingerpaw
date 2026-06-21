import SwiftUI

/// "Trail" design tokens — warm ginger palette on near-black, from the Claude design.
enum WS {
    static let bg = Color(hex: 0x0b0b0d)        // terminal / window body
    static let titlebar = Color(hex: 0x26272d)
    static let rail = Color(hex: 0x161719)       // icon rail
    static let panel = Color(hex: 0x1b1c21)      // sidebar + diff panel
    static let bar = Color(hex: 0x202126)        // tab bar + status bar

    static let accent = Color(hex: 0xf0a05e)     // ginger
    static let accentBtn = Color(hex: 0xc96a24)
    static let accentBtnHover = Color(hex: 0xd97a2e)
    static let accentSubtle = Color(hex: 0xe8843e).opacity(0.18)

    static let textPrimary = Color(hex: 0xf1f1f3)
    static let textSecondary = Color(hex: 0x9b9da4)
    static let textTertiary = Color(hex: 0x777981)
    static let textDim = Color(hex: 0x5b5d64)
    static let label = Color(hex: 0x6c6e76)

    static let add = Color(hex: 0x3fb950)
    static let del = Color(hex: 0xe5707a)
    static let running = Color(hex: 0x5a8de0)

    static let border = Color.white.opacity(0.06)
    static let rowSelected = Color.white.opacity(0.055)
    static let rowHover = Color.white.opacity(0.04)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
