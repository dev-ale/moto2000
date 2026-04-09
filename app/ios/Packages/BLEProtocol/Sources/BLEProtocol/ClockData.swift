import Foundation

/// Decoded body for a `clock` screen payload.
public struct ClockData: Equatable, Sendable {
    public static let encodedSize: Int = 12

    /// Seconds since the Unix epoch, UTC.
    public var unixTime: Int64
    /// Local timezone offset from UTC in minutes, range `-720..=840`.
    public var tzOffsetMinutes: Int16
    /// If `true`, the display shows 24-hour format.
    public var is24Hour: Bool

    public init(unixTime: Int64, tzOffsetMinutes: Int16, is24Hour: Bool) {
        self.unixTime = unixTime
        self.tzOffsetMinutes = tzOffsetMinutes
        self.is24Hour = is24Hour
    }

    static func decode(_ body: Data) throws -> ClockData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .clock,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let unixTime = try reader.readInt64()
        let tz = try reader.readInt16()
        let flags = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "clock.reserved")
        }
        guard (-720...840).contains(tz) else {
            throw BLEProtocolError.valueOutOfRange(field: "clock.tzOffsetMinutes")
        }
        guard (flags & 0b1111_1110) == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "clock.flags")
        }
        return ClockData(
            unixTime: unixTime,
            tzOffsetMinutes: tz,
            is24Hour: (flags & 0x01) != 0
        )
    }

    func encode() throws -> Data {
        guard (-720...840).contains(tzOffsetMinutes) else {
            throw BLEProtocolError.valueOutOfRange(field: "clock.tzOffsetMinutes")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeInt64(unixTime)
        writer.writeInt16(tzOffsetMinutes)
        writer.writeUInt8(is24Hour ? 0x01 : 0x00)
        writer.writeUInt8(0)  // reserved
        return writer.data
    }
}
