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
    /// Trigger the ESP32 to check for an OTA firmware update.
    case checkForOTAUpdate
    /// Set the ordered list of enabled screens. Payload: count + screen IDs.
    case setScreenOrder([ScreenID])

    /// Wire-format size of every fixed-size encoded command in bytes.
    public static let encodedSize: Int = 4

    /// Maximum number of screens in a `setScreenOrder` command.
    public static let maxScreenOrderCount: Int = 13

    /// Numeric command byte as documented in `docs/ble-protocol.md`.
    public var commandByte: UInt8 {
        switch self {
        case .setActiveScreen: return 0x01
        case .setBrightness:   return 0x02
        case .sleep:           return 0x03
        case .wake:            return 0x04
        case .clearAlertOverlay: return 0x05
        case .checkForOTAUpdate: return 0x06
        case .setScreenOrder:  return 0x07
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
        case .sleep, .wake, .clearAlertOverlay, .checkForOTAUpdate:
            writer.writeUInt8(0)
            writer.writeUInt8(0)
        case .setScreenOrder(let screens):
            writer.writeUInt8(UInt8(screens.count))
            for screen in screens {
                writer.writeUInt8(screen.rawValue)
            }
        }
        return writer.data
    }

    /// Decode a BLE write payload into a ``ControlCommand``.
    ///
    /// Fixed-size commands are 4 bytes. Variable-size commands (e.g.
    /// `setScreenOrder`) require at least 3 bytes (version + cmd + count).
    public static func decode(_ data: Data) throws -> ControlCommand {
        guard data.count >= 2 else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let cmd = try reader.readUInt8()

        // Variable-length command: setScreenOrder
        if cmd == 0x07 {
            guard reader.remaining >= 1 else {
                throw BLEProtocolError.truncatedHeader
            }
            let count = try reader.readUInt8()
            guard count <= Self.maxScreenOrderCount else {
                throw BLEProtocolError.invalidCommandValue(field: "screenOrder.count")
            }
            guard reader.remaining >= Int(count) else {
                throw BLEProtocolError.truncatedBody(declared: Int(count), available: reader.remaining)
            }
            var screens: [ScreenID] = []
            screens.reserveCapacity(Int(count))
            for _ in 0..<count {
                let raw = try reader.readUInt8()
                guard let screen = ScreenID(rawValue: raw) else {
                    throw BLEProtocolError.unknownScreenId(raw)
                }
                screens.append(screen)
            }
            return .setScreenOrder(screens)
        }

        // Fixed-size commands: need exactly 4 bytes total.
        guard data.count >= Self.encodedSize else {
            throw BLEProtocolError.truncatedHeader
        }
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
        case 0x06:
            guard value0 == 0, value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            return .checkForOTAUpdate
        default:
            throw BLEProtocolError.unknownCommand(cmd)
        }
    }
}
