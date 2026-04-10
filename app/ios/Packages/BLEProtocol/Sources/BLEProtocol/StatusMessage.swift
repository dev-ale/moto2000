import Foundation

/// A status notification sent from the ESP32 over the `status` characteristic.
///
/// Wire format (variable size, minimum 3 bytes):
///
/// ```
///  0       1       2
/// +-------+-------+-------+
/// |version|  type |  ...  |
/// +-------+-------+-------+
/// ```
///
/// `version` is ``BLEProtocolConstants/protocolVersion``. The payload after
/// `type` is type-specific.
public enum StatusMessage: Equatable, Sendable {
    /// The ESP32 switched to a different screen.
    case screenChanged(ScreenID)

    /// Numeric type byte as documented in `docs/ble-protocol.md`.
    public var typeByte: UInt8 {
        switch self {
        case .screenChanged: return 0x01
        }
    }

    /// Encode this status message into a BLE notify payload.
    public func encode() -> Data {
        var writer = ByteWriter()
        writer.writeUInt8(BLEProtocolConstants.protocolVersion)
        writer.writeUInt8(typeByte)
        switch self {
        case .screenChanged(let id):
            writer.writeUInt8(id.rawValue)
        }
        return writer.data
    }

    /// Decode a BLE notify payload into a ``StatusMessage``.
    public static func decode(_ data: Data) throws -> StatusMessage {
        guard data.count >= 3 else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let type = try reader.readUInt8()

        switch type {
        case 0x01:
            let raw = try reader.readUInt8()
            guard let screen = ScreenID(rawValue: raw) else {
                throw BLEProtocolError.unknownScreenId(raw)
            }
            return .screenChanged(screen)
        default:
            throw BLEProtocolError.unknownStatusType(type)
        }
    }
}
