import Foundation

/// Decoded body for a `compass` screen payload.
///
/// Layout (little-endian, 8 bytes total):
/// ```
/// offset 0..1 : uint16 magneticHeadingDegX10   (0..=3599)
/// offset 2..3 : uint16 trueHeadingDegX10       (0..=3599, or 0xFFFF = unknown)
/// offset 4..5 : uint16 headingAccuracyDegX10   (0..=3599)
/// offset 6    : uint8  flags
///                       bit 0: useTrueHeading — if set, the screen draws the
///                              true heading; otherwise the magnetic heading.
///                       bits 1..7: reserved, must be zero.
/// offset 7    : uint8  reserved                (must be zero)
/// ```
///
/// Matches `ble_compass_data_t` in the C codec.
public struct CompassData: Equatable, Sendable {
    public static let encodedSize: Int = 8

    /// Sentinel used in `trueHeadingDegX10` when the true-heading fix is not
    /// available from the iOS `CLLocationManager`.
    public static let trueHeadingUnknown: UInt16 = 0xFFFF

    public static let useTrueHeadingFlag: UInt8 = 1 << 0
    static let reservedFlagMask: UInt8 = 0b1111_1110

    /// Magnetic heading × 10. Range `0..=3599`.
    public var magneticHeadingDegX10: UInt16
    /// True heading × 10, or `0xFFFF` if unknown. Otherwise `0..=3599`.
    public var trueHeadingDegX10: UInt16
    /// Reported heading accuracy × 10, in degrees. Range `0..=3599`.
    public var headingAccuracyDegX10: UInt16
    /// Raw flags byte. Bit 0 selects true vs magnetic heading for display.
    public var flags: UInt8

    public init(
        magneticHeadingDegX10: UInt16,
        trueHeadingDegX10: UInt16,
        headingAccuracyDegX10: UInt16,
        flags: UInt8
    ) {
        self.magneticHeadingDegX10 = magneticHeadingDegX10
        self.trueHeadingDegX10 = trueHeadingDegX10
        self.headingAccuracyDegX10 = headingAccuracyDegX10
        self.flags = flags
    }

    /// If true, the dashboard should render the true heading; otherwise magnetic.
    public var useTrueHeading: Bool {
        (flags & Self.useTrueHeadingFlag) != 0
    }

    static func decode(_ body: Data) throws -> CompassData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .compass,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let magnetic = try reader.readUInt16()
        let trueHeading = try reader.readUInt16()
        let accuracy = try reader.readUInt16()
        let flags = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "compass.reserved")
        }
        guard (flags & Self.reservedFlagMask) == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "compass.flags")
        }
        guard magnetic <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.magneticHeadingDegX10")
        }
        guard trueHeading <= 3599 || trueHeading == Self.trueHeadingUnknown else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.trueHeadingDegX10")
        }
        guard accuracy <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.headingAccuracyDegX10")
        }
        return CompassData(
            magneticHeadingDegX10: magnetic,
            trueHeadingDegX10: trueHeading,
            headingAccuracyDegX10: accuracy,
            flags: flags
        )
    }

    func encode() throws -> Data {
        guard magneticHeadingDegX10 <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.magneticHeadingDegX10")
        }
        guard trueHeadingDegX10 <= 3599 || trueHeadingDegX10 == Self.trueHeadingUnknown else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.trueHeadingDegX10")
        }
        guard headingAccuracyDegX10 <= 3599 else {
            throw BLEProtocolError.valueOutOfRange(field: "compass.headingAccuracyDegX10")
        }
        guard (flags & Self.reservedFlagMask) == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "compass.flags")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt16(magneticHeadingDegX10)
        writer.writeUInt16(trueHeadingDegX10)
        writer.writeUInt16(headingAccuracyDegX10)
        writer.writeUInt8(flags)
        writer.writeUInt8(0)  // reserved
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
