import Foundation

/// Turn-by-turn maneuver type as it appears on the wire.
public enum ManeuverType: UInt8, Sendable, CaseIterable, Equatable {
    case none = 0x00
    case straight = 0x01
    case slightLeft = 0x02
    case left = 0x03
    case sharpLeft = 0x04
    case uTurnLeft = 0x05
    case slightRight = 0x06
    case right = 0x07
    case sharpRight = 0x08
    case uTurnRight = 0x09
    case roundaboutEnter = 0x0A
    case roundaboutExit = 0x0B
    case merge = 0x0C
    case forkLeft = 0x0D
    case forkRight = 0x0E
    case arrive = 0x0F
}

/// Decoded body for a `navigation` screen payload.
public struct NavData: Equatable, Sendable {
    public static let encodedSize: Int = 56
    public static let unknownU16: UInt16 = 0xFFFF

    public var latitudeE7: Int32
    public var longitudeE7: Int32
    /// Speed × 10, so 455 = 45.5 km/h. Max 3000 (300.0 km/h).
    public var speedKmhX10: UInt16
    /// Heading × 10. Range `0..=3599`.
    public var headingDegX10: UInt16
    /// Metres to next maneuver. `0xFFFF` = unknown.
    public var distanceToManeuverMeters: UInt16
    public var maneuver: ManeuverType
    /// Fixed-length UTF-8 string, ≤ 31 bytes to leave room for a terminator.
    public var streetName: String
    /// Minutes to destination. `0xFFFF` = unknown.
    public var etaMinutes: UInt16
    /// Remaining distance × 10. `0xFFFF` = unknown.
    public var remainingKmX10: UInt16

    public init(
        latitudeE7: Int32,
        longitudeE7: Int32,
        speedKmhX10: UInt16,
        headingDegX10: UInt16,
        distanceToManeuverMeters: UInt16,
        maneuver: ManeuverType,
        streetName: String,
        etaMinutes: UInt16,
        remainingKmX10: UInt16
    ) {
        self.latitudeE7 = latitudeE7
        self.longitudeE7 = longitudeE7
        self.speedKmhX10 = speedKmhX10
        self.headingDegX10 = headingDegX10
        self.distanceToManeuverMeters = distanceToManeuverMeters
        self.maneuver = maneuver
        self.streetName = streetName
        self.etaMinutes = etaMinutes
        self.remainingKmX10 = remainingKmX10
    }

    static func decode(_ body: Data) throws -> NavData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .navigation,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let lat = try reader.readInt32()
        let lng = try reader.readInt32()
        let speed = try reader.readUInt16()
        let heading = try reader.readUInt16()
        let distance = try reader.readUInt16()
        let maneuverRaw = try reader.readUInt8()
        let reserved1 = try reader.readUInt8()
        guard reserved1 == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "nav.reserved1")
        }
        guard let maneuver = ManeuverType(rawValue: maneuverRaw) else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.maneuver")
        }
        let street = try reader.readFixedString(length: 32)
        let eta = try reader.readUInt16()
        let remaining = try reader.readUInt16()
        let reserved2 = try reader.readUInt32()
        guard reserved2 == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "nav.reserved2")
        }
        guard (-900_000_000...900_000_000).contains(lat) else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.latitudeE7")
        }
        guard (-1_800_000_000...1_800_000_000).contains(lng) else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.longitudeE7")
        }
        guard speed <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.speedKmhX10")
        }
        guard heading <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.headingDegX10")
        }
        return NavData(
            latitudeE7: lat,
            longitudeE7: lng,
            speedKmhX10: speed,
            headingDegX10: heading,
            distanceToManeuverMeters: distance,
            maneuver: maneuver,
            streetName: street,
            etaMinutes: eta,
            remainingKmX10: remaining
        )
    }

    func encode() throws -> Data {
        guard (-900_000_000...900_000_000).contains(latitudeE7) else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.latitudeE7")
        }
        guard (-1_800_000_000...1_800_000_000).contains(longitudeE7) else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.longitudeE7")
        }
        guard speedKmhX10 <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.speedKmhX10")
        }
        guard headingDegX10 <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "nav.headingDegX10")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeInt32(latitudeE7)
        writer.writeInt32(longitudeE7)
        writer.writeUInt16(speedKmhX10)
        writer.writeUInt16(headingDegX10)
        writer.writeUInt16(distanceToManeuverMeters)
        writer.writeUInt8(maneuver.rawValue)
        writer.writeUInt8(0)
        try writer.writeFixedString(streetName, length: 32)
        writer.writeUInt16(etaMinutes)
        writer.writeUInt16(remainingKmX10)
        writer.writeUInt32(0)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
