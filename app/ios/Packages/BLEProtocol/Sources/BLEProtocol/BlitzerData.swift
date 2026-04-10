import Foundation

/// Decoded body for a `blitzer` screen payload (radar / speed-camera alert).
///
/// Layout (little-endian, 8 bytes total):
/// ```
/// offset 0     : uint16  distance_meters          Distance to nearest camera in metres.
/// offset 2     : uint16  speed_limit_kmh          Speed limit at the camera. 0xFFFF = unknown.
/// offset 4     : uint16  current_speed_kmh_x10    Current speed × 10 (from GPS).
/// offset 6     : uint8   camera_type              0x00=fixed, 0x01=mobile, 0x02=red_light, 0x03=section, 0x04=unknown
/// offset 7     : uint8   reserved                 Must be 0.
/// ```
///
/// The `ALERT` header flag should be set when `distance_meters < alert_radius`
/// and cleared when the camera is no longer in range. This signals the ESP32
/// screen FSM to treat the payload as a priority overlay.
///
/// Matches `ble_blitzer_data_t` in the C codec.
public struct BlitzerData: Equatable, Sendable {
    public static let encodedSize: Int = 8

    /// Speed-limit sentinel when the limit is not known.
    public static let unknownSpeedLimit: UInt16 = 0xFFFF

    public enum CameraTypeWire: UInt8, Equatable, Sendable, CaseIterable {
        case fixed    = 0x00
        case mobile   = 0x01
        case redLight = 0x02
        case section  = 0x03
        case unknown  = 0x04
    }

    public var distanceMeters: UInt16
    public var speedLimitKmh: UInt16
    public var currentSpeedKmhX10: UInt16
    public var cameraType: CameraTypeWire

    public init(
        distanceMeters: UInt16,
        speedLimitKmh: UInt16,
        currentSpeedKmhX10: UInt16,
        cameraType: CameraTypeWire
    ) {
        self.distanceMeters = distanceMeters
        self.speedLimitKmh = speedLimitKmh
        self.currentSpeedKmhX10 = currentSpeedKmhX10
        self.cameraType = cameraType
    }

    static func decode(_ body: Data) throws -> BlitzerData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .blitzer,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let distance = try reader.readUInt16()
        let speedLimit = try reader.readUInt16()
        let currentSpeed = try reader.readUInt16()
        let typeRaw = try reader.readUInt8()
        guard let cameraType = CameraTypeWire(rawValue: typeRaw) else {
            throw BLEProtocolError.valueOutOfRange(field: "blitzer.camera_type")
        }
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "blitzer.reserved")
        }

        return BlitzerData(
            distanceMeters: distance,
            speedLimitKmh: speedLimit,
            currentSpeedKmhX10: currentSpeed,
            cameraType: cameraType
        )
    }

    func encode() throws -> Data {
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt16(distanceMeters)
        writer.writeUInt16(speedLimitKmh)
        writer.writeUInt16(currentSpeedKmhX10)
        writer.writeUInt8(cameraType.rawValue)
        writer.writeUInt8(0) // reserved
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
