import Foundation

/// Bitfield flags carried in every screen payload header.
public struct ScreenFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Payload is an alert overlay with priority.
    public static let alert = ScreenFlags(rawValue: 1 << 0)

    /// Render in the night palette.
    public static let nightMode = ScreenFlags(rawValue: 1 << 1)

    /// Data is stale — renderer shows a staleness indicator.
    public static let stale = ScreenFlags(rawValue: 1 << 2)

    /// Bits 3..7 are reserved and must be zero on the wire.
    public static let reservedMask: UInt8 = 0b1111_1000
}
