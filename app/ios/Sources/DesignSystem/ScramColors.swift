import SwiftUI

extension Color {
    // MARK: - Core

    static let scramBackground = Color(hex: 0x000000)
    static let scramSurface = Color(hex: 0x111111)
    static let scramSurfaceElevated = Color(hex: 0x1A1A1A)
    static let scramBorder = Color(hex: 0x222222)
    static let scramBorderSubtle = Color(hex: 0x333333)

    // MARK: - Text

    static let scramTextPrimary = Color(hex: 0xFFFFFF)
    static let scramTextSecondary = Color(hex: 0x999999)
    static let scramTextTertiary = Color(hex: 0x666666)
    static let scramTextDisabled = Color(hex: 0x444444)

    // MARK: - Semantic

    static let scramGreen = Color(hex: 0xF5A623)
    static let scramGreenBg = Color(hex: 0x2A2010)
    static let scramRed = Color(hex: 0xE24B4A)
    static let scramRedBg = Color(hex: 0x2A1A1A)
    static let scramBlue = Color(hex: 0x5BACF5)
    static let scramAmber = Color(hex: 0xF5A623)
    static let scramPurple = Color(hex: 0xC084FC)

    // MARK: - Hex init

    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
