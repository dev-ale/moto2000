import Foundation

/// Identifier for a screen type on the dashboard.
///
/// Values match the table in `docs/ble-protocol.md`. Decoders reject any value
/// not listed here.
public enum ScreenID: UInt8, Sendable, CaseIterable {
    case navigation = 0x01
    case speedHeading = 0x02
    case compass = 0x03
    case weather = 0x04
    case tripStats = 0x05
    case music = 0x06
    case leanAngle = 0x07
    case blitzer = 0x08
    case incomingCall = 0x09
    case fuelEstimate = 0x0A
    case altitude = 0x0B
    case appointment = 0x0C
    case clock = 0x0D

    /// Expected body size in bytes for this screen, or `nil` if variable/unknown.
    public var expectedBodySize: Int? {
        switch self {
        case .clock: return ClockData.encodedSize
        case .navigation: return NavData.encodedSize
        default: return nil
        }
    }
}
