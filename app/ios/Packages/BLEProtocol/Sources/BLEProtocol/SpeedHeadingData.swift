import Foundation

/// Decoded body for a `speedHeading` screen payload.
///
/// Layout (little-endian, 8 bytes total):
/// ```
/// offset 0..1 : uint16 speedKmhX10       (0..=3000)
/// offset 2..3 : uint16 headingDegX10     (0..=3599)
/// offset 4..5 : int16  altitudeMeters    (-500..=9000)
/// offset 6..7 : int16  temperatureCelsiusX10 (-500..=600)
/// ```
///
/// Matches `ble_speed_heading_data_t` in the C codec.
public struct SpeedHeadingData: Equatable, Sendable {
    public static let encodedSize: Int = 8

    /// Ground speed × 10, so 455 = 45.5 km/h. Max 3000 (300.0 km/h).
    public var speedKmhX10: UInt16
    /// Heading × 10. Range `0..=3599`.
    public var headingDegX10: UInt16
    /// Altitude in metres above sea level, range `-500..=9000`.
    public var altitudeMeters: Int16
    /// Ambient temperature × 10 in °C, range `-500..=600`.
    public var temperatureCelsiusX10: Int16

    public init(
        speedKmhX10: UInt16,
        headingDegX10: UInt16,
        altitudeMeters: Int16,
        temperatureCelsiusX10: Int16
    ) {
        self.speedKmhX10 = speedKmhX10
        self.headingDegX10 = headingDegX10
        self.altitudeMeters = altitudeMeters
        self.temperatureCelsiusX10 = temperatureCelsiusX10
    }

    static func decode(_ body: Data) throws -> SpeedHeadingData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .speedHeading,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let speed = try reader.readUInt16()
        let heading = try reader.readUInt16()
        let altitude = try reader.readInt16()
        let temperature = try reader.readInt16()
        guard speed <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.speedKmhX10")
        }
        guard heading <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.headingDegX10")
        }
        guard (-500...9000).contains(altitude) else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.altitudeMeters")
        }
        guard (-500...600).contains(temperature) else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.temperatureCelsiusX10")
        }
        return SpeedHeadingData(
            speedKmhX10: speed,
            headingDegX10: heading,
            altitudeMeters: altitude,
            temperatureCelsiusX10: temperature
        )
    }

    func encode() throws -> Data {
        guard speedKmhX10 <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.speedKmhX10")
        }
        guard headingDegX10 <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.headingDegX10")
        }
        guard (-500...9000).contains(altitudeMeters) else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.altitudeMeters")
        }
        guard (-500...600).contains(temperatureCelsiusX10) else {
            throw BLEProtocolError.valueOutOfRange(field: "speedHeading.temperatureCelsiusX10")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt16(speedKmhX10)
        writer.writeUInt16(headingDegX10)
        writer.writeInt16(altitudeMeters)
        writer.writeInt16(temperatureCelsiusX10)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
