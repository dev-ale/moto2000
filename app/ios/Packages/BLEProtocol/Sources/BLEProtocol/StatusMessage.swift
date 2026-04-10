import Foundation

/// A notification sent from the ESP32 over the `status` characteristic.
///
/// Wire format (4 bytes total):
///
/// ```
///  0       1       2       3
/// +-------+-------+-------+-------+
/// |version| type  |   value...    |
/// +-------+-------+-------+-------+
/// ```
///
/// `version` is ``BLEProtocolConstants/protocolVersion``. The `value` region
/// is always 2 bytes; messages that don't need both leave the trailing byte
/// zero.
public enum StatusMessage: Equatable, Sendable {
    /// The firmware switched the active screen (via handlebar button).
    case screenChanged(ScreenID)

    /// Wire-format size in bytes.
    public static let encodedSize: Int = 4

    /// Decode a 4-byte status notification from the ESP32.
    public static func decode(_ data: Data) throws -> StatusMessage {
        guard data.count >= encodedSize else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let type = try reader.readUInt8()
        let value0 = try reader.readUInt8()
        let value1 = try reader.readUInt8()

        switch type {
        case 0x01:
            guard value1 == 0 else {
                throw BLEProtocolError.invalidReserved
            }
            guard let screen = ScreenID(rawValue: value0) else {
                throw BLEProtocolError.unknownScreenId(value0)
            }
            return .screenChanged(screen)
        default:
            throw BLEProtocolError.unknownCommand(type)
        }
    }

    /// Encode this status message into a 4-byte payload.
    public func encode() -> Data {
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(BLEProtocolConstants.protocolVersion)
        switch self {
        case .screenChanged(let id):
            writer.writeUInt8(0x01)
            writer.writeUInt8(id.rawValue)
            writer.writeUInt8(0)
        }
        return writer.data
    }
}
