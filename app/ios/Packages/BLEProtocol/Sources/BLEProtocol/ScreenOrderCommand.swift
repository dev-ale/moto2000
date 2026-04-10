import Foundation

/// A variable-length control command that sets the ordered list of enabled
/// screens on the ESP32.
///
/// Wire format:
///
/// ```
///  0       1       2       3       4     ...     2+N
/// +-------+-------+-------+-------+-------+-------+
/// |version|  0x10 | count |  id_0 |  id_1 | id_N  |
/// +-------+-------+-------+-------+-------+-------+
/// ```
///
/// Unlike ``ControlCommand`` (which is always 4 bytes), this command has a
/// variable length of `3 + count` bytes.
public struct ScreenOrderCommand: Equatable, Sendable {
    /// The ordered list of enabled screen IDs.
    public let screenIDs: [ScreenID]

    /// The command byte used on the wire.
    public static let commandByte: UInt8 = 0x10

    /// Maximum number of screens that can be sent in one command.
    public static let maxScreens: Int = 16

    public init(screenIDs: [ScreenID]) {
        self.screenIDs = screenIDs
    }

    /// Encode into a BLE write payload.
    public func encode() throws -> Data {
        guard screenIDs.count <= Self.maxScreens else {
            throw BLEProtocolError.valueOutOfRange(
                field: "screenIDs.count \(screenIDs.count) exceeds max \(Self.maxScreens)"
            )
        }
        var writer = ByteWriter(capacity: 3 + screenIDs.count)
        writer.writeUInt8(BLEProtocolConstants.protocolVersion)
        writer.writeUInt8(Self.commandByte)
        writer.writeUInt8(UInt8(screenIDs.count))
        for id in screenIDs {
            writer.writeUInt8(id.rawValue)
        }
        return writer.data
    }

    /// Decode a BLE write payload into a ``ScreenOrderCommand``.
    public static func decode(_ data: Data) throws -> ScreenOrderCommand {
        guard data.count >= 3 else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let cmd = try reader.readUInt8()
        guard cmd == commandByte else {
            throw BLEProtocolError.unknownCommand(cmd)
        }
        let count = Int(try reader.readUInt8())
        guard count <= maxScreens else {
            throw BLEProtocolError.valueOutOfRange(
                field: "screen count \(count) exceeds max \(maxScreens)"
            )
        }
        guard reader.remaining >= count else {
            throw BLEProtocolError.truncatedBody(declared: count, available: reader.remaining)
        }
        var ids: [ScreenID] = []
        for _ in 0..<count {
            let raw = try reader.readUInt8()
            guard let id = ScreenID(rawValue: raw) else {
                throw BLEProtocolError.unknownScreenId(raw)
            }
            ids.append(id)
        }
        return ScreenOrderCommand(screenIDs: ids)
    }
}
