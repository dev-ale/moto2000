import Foundation

/// Decoded body for a `leanAngle` screen payload.
///
/// Layout (little-endian, 8 bytes total):
/// ```
/// offset 0..1 : int16  currentLeanDegX10        (-900..=900)
///                       Negative = left lean, positive = right lean.
/// offset 2..3 : uint16 maxLeftLeanDegX10        (0..=900)   unsigned magnitude
/// offset 4..5 : uint16 maxRightLeanDegX10       (0..=900)
/// offset 6    : uint8  confidencePercent        (0..=100)
/// offset 7    : uint8  reserved                 (must be zero)
/// ```
///
/// Matches `ble_lean_angle_data_t` in the C codec.
public struct LeanAngleData: Equatable, Sendable {
    public static let encodedSize: Int = 8

    /// Maximum absolute lean angle that fits in the wire format, in tenths of
    /// a degree. Equivalent to ±90.0°.
    public static let maxAbsoluteLeanX10: Int16 = 900

    /// Current lean × 10. Negative = left lean, positive = right lean.
    public var currentLeanDegX10: Int16
    /// Maximum left lean magnitude × 10 (unsigned). Range `0..=900`.
    public var maxLeftLeanDegX10: UInt16
    /// Maximum right lean magnitude × 10 (unsigned). Range `0..=900`.
    public var maxRightLeanDegX10: UInt16
    /// Renderer confidence in the calculation, in percent. Range `0..=100`.
    public var confidencePercent: UInt8

    public init(
        currentLeanDegX10: Int16,
        maxLeftLeanDegX10: UInt16,
        maxRightLeanDegX10: UInt16,
        confidencePercent: UInt8
    ) {
        self.currentLeanDegX10 = currentLeanDegX10
        self.maxLeftLeanDegX10 = maxLeftLeanDegX10
        self.maxRightLeanDegX10 = maxRightLeanDegX10
        self.confidencePercent = confidencePercent
    }

    static func decode(_ body: Data) throws -> LeanAngleData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .leanAngle,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let current = try reader.readInt16()
        let maxLeft = try reader.readUInt16()
        let maxRight = try reader.readUInt16()
        let confidence = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "leanAngle.reserved")
        }
        guard current >= -Self.maxAbsoluteLeanX10, current <= Self.maxAbsoluteLeanX10 else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.currentLeanDegX10")
        }
        guard maxLeft <= UInt16(Self.maxAbsoluteLeanX10) else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.maxLeftLeanDegX10")
        }
        guard maxRight <= UInt16(Self.maxAbsoluteLeanX10) else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.maxRightLeanDegX10")
        }
        guard confidence <= 100 else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.confidencePercent")
        }
        return LeanAngleData(
            currentLeanDegX10: current,
            maxLeftLeanDegX10: maxLeft,
            maxRightLeanDegX10: maxRight,
            confidencePercent: confidence
        )
    }

    func encode() throws -> Data {
        guard
            currentLeanDegX10 >= -Self.maxAbsoluteLeanX10,
            currentLeanDegX10 <= Self.maxAbsoluteLeanX10
        else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.currentLeanDegX10")
        }
        guard maxLeftLeanDegX10 <= UInt16(Self.maxAbsoluteLeanX10) else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.maxLeftLeanDegX10")
        }
        guard maxRightLeanDegX10 <= UInt16(Self.maxAbsoluteLeanX10) else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.maxRightLeanDegX10")
        }
        guard confidencePercent <= 100 else {
            throw BLEProtocolError.valueOutOfRange(field: "leanAngle.confidencePercent")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeInt16(currentLeanDegX10)
        writer.writeUInt16(maxLeftLeanDegX10)
        writer.writeUInt16(maxRightLeanDegX10)
        writer.writeUInt8(confidencePercent)
        writer.writeUInt8(0)  // reserved
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
