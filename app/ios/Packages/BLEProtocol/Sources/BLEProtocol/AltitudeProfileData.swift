import Foundation

/// Decoded body for an `altitude` screen payload.
///
/// Layout (little-endian, 128 bytes total):
/// ```
/// offset 0..1   : int16  current_altitude_m      -500..=9000
/// offset 2..3   : uint16 total_ascent_m
/// offset 4..5   : uint16 total_descent_m
/// offset 6      : uint8  sample_count             0..=60
/// offset 7      : uint8  reserved                 must be 0
/// offset 8..127 : int16[60] profile               altitude samples in meters
/// ```
///
/// Matches `ble_altitude_profile_data_t` in the C codec.
public struct AltitudeProfileData: Equatable, Sendable {
    public static let encodedSize: Int = 128
    public static let maxSamples: Int = 60

    public var currentAltitudeM: Int16
    public var totalAscentM: UInt16
    public var totalDescentM: UInt16
    public var sampleCount: UInt8
    public var profile: [Int16]  // always 60 elements on wire; only first sampleCount are meaningful

    public init(
        currentAltitudeM: Int16,
        totalAscentM: UInt16,
        totalDescentM: UInt16,
        sampleCount: UInt8,
        profile: [Int16]
    ) {
        self.currentAltitudeM = currentAltitudeM
        self.totalAscentM = totalAscentM
        self.totalDescentM = totalDescentM
        self.sampleCount = sampleCount
        self.profile = profile
    }

    static func decode(_ body: Data) throws -> AltitudeProfileData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .altitude,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let currentAlt = try reader.readInt16()
        let ascent = try reader.readUInt16()
        let descent = try reader.readUInt16()
        let sampleCount = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "altitude.reserved")
        }
        guard sampleCount <= Self.maxSamples else {
            throw BLEProtocolError.valueOutOfRange(field: "altitude.sample_count")
        }
        guard currentAlt >= -500 && currentAlt <= 9000 else {
            throw BLEProtocolError.valueOutOfRange(field: "altitude.current_altitude_m")
        }

        var profile = [Int16]()
        profile.reserveCapacity(Self.maxSamples)
        for _ in 0..<Self.maxSamples {
            profile.append(try reader.readInt16())
        }

        return AltitudeProfileData(
            currentAltitudeM: currentAlt,
            totalAscentM: ascent,
            totalDescentM: descent,
            sampleCount: sampleCount,
            profile: profile
        )
    }

    func encode() throws -> Data {
        guard sampleCount <= Self.maxSamples else {
            throw BLEProtocolError.valueOutOfRange(field: "altitude.sample_count")
        }
        guard currentAltitudeM >= -500 && currentAltitudeM <= 9000 else {
            throw BLEProtocolError.valueOutOfRange(field: "altitude.current_altitude_m")
        }

        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeInt16(currentAltitudeM)
        writer.writeUInt16(totalAscentM)
        writer.writeUInt16(totalDescentM)
        writer.writeUInt8(sampleCount)
        writer.writeUInt8(0) // reserved
        // Write all 60 profile slots; pad with 0 beyond what's provided.
        for i in 0..<Self.maxSamples {
            if i < profile.count {
                writer.writeInt16(profile[i])
            } else {
                writer.writeInt16(0)
            }
        }
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
