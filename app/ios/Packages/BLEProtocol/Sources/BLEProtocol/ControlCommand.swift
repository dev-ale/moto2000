import Foundation

/// A command sent to the ESP32 over the `control` characteristic.
///
/// Wire format (4 bytes total):
///
/// ```
///  0       1       2       3
/// +-------+-------+-------+-------+
/// |version|  cmd  |   value...    |
/// +-------+-------+-------+-------+
/// ```
///
/// `version` is ``BLEProtocolConstants/protocolVersion``. The `value` region
/// is always 2 bytes; commands that don't need both bytes leave the unused
/// trailing bytes zero. Decoders must reject non-zero reserved bytes.
public enum ControlCommand: Equatable, Sendable {
    /// Switch the active persistent screen.
    case setActiveScreen(ScreenID)
    /// Set the panel brightness as a 0-100 percentage.
    case setBrightness(UInt8)
    /// Dim the panel and enter sleep state.
    case sleep
    /// Wake the panel from sleep.
    case wake
    /// Clear any active alert overlay and return to the previously selected
    /// screen.
    case clearAlertOverlay

    /// Wire-format size of every encoded command in bytes.
    public static let encodedSize: Int = 4

    /// Numeric command byte as documented in `docs/ble-protocol.md`.
    public var commandByte: UInt8 {
        switch self {
        case .setActiveScreen: return 0x01
        case .setBrightness:   return 0x02
        case .sleep:           return 0x03
        case .wake:            return 0x04
        case .clearAlertOverlay: return 0x05
        }
    }

    /// Encode this command into a 4-byte BLE write payload.
    public func encode() -> Data {
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(BLEProtocolConstants.protocolVersion)
        writer.writeUInt8(commandByte)
        switch self {
        case .setActiveScreen(let id):
            writer.writeUInt8(id.rawValue)
            writer.writeUInt8(0)
        case .setBrightness(let percent):
            writer.writeUInt8(percent)
            writer.writeUInt8(0)
        case .sleep, .wake, .clearAlertOverlay:
            writer.writeUInt8(0)
            writer.writeUInt8(0)
        }
        return writer.data
    }

    /// Decode a 4-byte BLE write payload into a ``ControlCommand``.
    public static func decode(_ data: Data) throws -> ControlCommand {
        guard data.count >= Self.encodedSize else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let cmd = try reader.readUInt8()
        let value0 = try reader.readUInt8()
        let value1 = try reader.readUInt8()

        switch cmd {
        case 0x01:
            guard value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            guard let screen = ScreenID(rawValue: value0) else {
                throw BLEProtocolError.unknownScreenId(value0)
            }
            return .setActiveScreen(screen)
        case 0x02:
            guard value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            guard value0 <= 100 else {
                throw BLEProtocolError.invalidCommandValue(field: "brightness")
            }
            return .setBrightness(value0)
        case 0x03:
            guard value0 == 0, value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            return .sleep
        case 0x04:
            guard value0 == 0, value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            return .wake
        case 0x05:
            guard value0 == 0, value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            return .clearAlertOverlay
        default:
            throw BLEProtocolError.unknownCommand(cmd)
        }
    }
}
