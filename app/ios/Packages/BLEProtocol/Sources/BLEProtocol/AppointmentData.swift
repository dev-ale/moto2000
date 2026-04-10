import Foundation

/// Decoded body for an `appointment` screen payload.
///
/// Layout (little-endian, 60 bytes total):
/// ```
/// offset 0..1  : int16   starts_in_minutes  (-1440..=10080)
/// offset 2..33 : char[32] title  (UTF-8, null-terminated, <=31 bytes)
/// offset 34..57: char[24] location (UTF-8, null-terminated, <=23 bytes)
/// offset 58..59: uint16  reserved (must be 0)
/// ```
///
/// Matches `ble_appointment_data_t` in the C codec.
public struct AppointmentData: Equatable, Sendable {
    public static let encodedSize: Int = 60

    public static let titleFieldLength: Int = 32
    public static let locationFieldLength: Int = 24

    public static let minStartsInMinutes: Int16 = -1440
    public static let maxStartsInMinutes: Int16 = 10080

    /// Minutes until event start. Negative = already started.
    /// Range `-1440..=10080`.
    public var startsInMinutes: Int16
    /// Fixed-length UTF-8 string, <= 31 bytes to leave room for a terminator.
    public var title: String
    /// Fixed-length UTF-8 string, <= 23 bytes.
    public var location: String

    public init(
        startsInMinutes: Int16,
        title: String,
        location: String
    ) {
        self.startsInMinutes = startsInMinutes
        self.title = title
        self.location = location
    }

    static func decode(_ body: Data) throws -> AppointmentData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .appointment,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let minutes = try reader.readInt16()
        guard minutes >= Self.minStartsInMinutes && minutes <= Self.maxStartsInMinutes else {
            throw BLEProtocolError.valueOutOfRange(field: "appointment.startsInMinutes")
        }
        let title = try reader.readFixedString(length: Self.titleFieldLength)
        let location = try reader.readFixedString(length: Self.locationFieldLength)
        let reserved = try reader.readUInt16()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "appointment.reserved")
        }
        return AppointmentData(
            startsInMinutes: minutes,
            title: title,
            location: location
        )
    }

    func encode() throws -> Data {
        guard startsInMinutes >= Self.minStartsInMinutes &&
              startsInMinutes <= Self.maxStartsInMinutes else {
            throw BLEProtocolError.valueOutOfRange(field: "appointment.startsInMinutes")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeInt16(startsInMinutes)
        try writer.writeFixedString(title, length: Self.titleFieldLength)
        try writer.writeFixedString(location, length: Self.locationFieldLength)
        writer.writeUInt16(0) // reserved
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
