import Foundation

/// Decoded body for a `tripStats` screen payload.
///
/// Layout (little-endian, 16 bytes total):
/// ```
/// offset  0..3 : uint32 rideTimeSeconds
/// offset  4..7 : uint32 distanceMeters
/// offset  8..9 : uint16 averageSpeedKmhX10   (0..=3000)
/// offset 10..11: uint16 maxSpeedKmhX10       (0..=3000)
/// offset 12..13: uint16 ascentMeters
/// offset 14..15: uint16 descentMeters
/// ```
///
/// Matches `ble_trip_stats_data_t` in the C codec.
public struct TripStatsData: Equatable, Sendable {
    public static let encodedSize: Int = 16

    /// Total accumulated ride time in seconds.
    public var rideTimeSeconds: UInt32
    /// Total accumulated distance in metres.
    public var distanceMeters: UInt32
    /// Average ground speed × 10. Range `0..=3000` (300.0 km/h).
    public var averageSpeedKmhX10: UInt16
    /// Max recorded ground speed × 10. Range `0..=3000`.
    public var maxSpeedKmhX10: UInt16
    /// Total positive elevation change in metres.
    public var ascentMeters: UInt16
    /// Total negative elevation change (magnitude) in metres.
    public var descentMeters: UInt16

    public init(
        rideTimeSeconds: UInt32,
        distanceMeters: UInt32,
        averageSpeedKmhX10: UInt16,
        maxSpeedKmhX10: UInt16,
        ascentMeters: UInt16,
        descentMeters: UInt16
    ) {
        self.rideTimeSeconds = rideTimeSeconds
        self.distanceMeters = distanceMeters
        self.averageSpeedKmhX10 = averageSpeedKmhX10
        self.maxSpeedKmhX10 = maxSpeedKmhX10
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
    }

    static func decode(_ body: Data) throws -> TripStatsData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .tripStats,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let rideTime = try reader.readUInt32()
        let distance = try reader.readUInt32()
        let avgSpeed = try reader.readUInt16()
        let maxSpeed = try reader.readUInt16()
        let ascent = try reader.readUInt16()
        let descent = try reader.readUInt16()
        guard avgSpeed <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "tripStats.averageSpeedKmhX10")
        }
        guard maxSpeed <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "tripStats.maxSpeedKmhX10")
        }
        return TripStatsData(
            rideTimeSeconds: rideTime,
            distanceMeters: distance,
            averageSpeedKmhX10: avgSpeed,
            maxSpeedKmhX10: maxSpeed,
            ascentMeters: ascent,
            descentMeters: descent
        )
    }

    func encode() throws -> Data {
        guard averageSpeedKmhX10 <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "tripStats.averageSpeedKmhX10")
        }
        guard maxSpeedKmhX10 <= 3000 else {
            throw BLEProtocolError.valueOutOfRange(field: "tripStats.maxSpeedKmhX10")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt32(rideTimeSeconds)
        writer.writeUInt32(distanceMeters)
        writer.writeUInt16(averageSpeedKmhX10)
        writer.writeUInt16(maxSpeedKmhX10)
        writer.writeUInt16(ascentMeters)
        writer.writeUInt16(descentMeters)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
