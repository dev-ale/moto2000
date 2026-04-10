import Foundation

/// Decoded body for a `fuelEstimate` screen payload.
///
/// Layout (little-endian, 8 bytes total):
/// ```
/// offset 0     : uint8  tank_percent             0..100
/// offset 1     : uint8  reserved                 must be 0
/// offset 2..3  : uint16 estimated_range_km       0xFFFF = unknown
/// offset 4..5  : uint16 consumption_ml_per_km    0xFFFF = unknown
/// offset 6..7  : uint16 fuel_remaining_ml        0xFFFF = unknown
/// ```
///
/// Matches `ble_fuel_data_t` in the C codec.
public struct FuelData: Equatable, Sendable {
    public static let encodedSize: Int = 8

    /// Sentinel for "unknown" on any uint16 field.
    public static let unknown: UInt16 = 0xFFFF

    public var tankPercent: UInt8
    public var estimatedRangeKm: UInt16
    public var consumptionMlPerKm: UInt16
    public var fuelRemainingMl: UInt16

    public init(
        tankPercent: UInt8,
        estimatedRangeKm: UInt16,
        consumptionMlPerKm: UInt16,
        fuelRemainingMl: UInt16
    ) {
        self.tankPercent = tankPercent
        self.estimatedRangeKm = estimatedRangeKm
        self.consumptionMlPerKm = consumptionMlPerKm
        self.fuelRemainingMl = fuelRemainingMl
    }

    static func decode(_ body: Data) throws -> FuelData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .fuelEstimate,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let tankPercent = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "fuel.reserved")
        }
        guard tankPercent <= 100 else {
            throw BLEProtocolError.valueOutOfRange(field: "fuel.tank_percent")
        }
        let rangeKm = try reader.readUInt16()
        let consumption = try reader.readUInt16()
        let remaining = try reader.readUInt16()

        return FuelData(
            tankPercent: tankPercent,
            estimatedRangeKm: rangeKm,
            consumptionMlPerKm: consumption,
            fuelRemainingMl: remaining
        )
    }

    func encode() throws -> Data {
        guard tankPercent <= 100 else {
            throw BLEProtocolError.valueOutOfRange(field: "fuel.tank_percent")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(tankPercent)
        writer.writeUInt8(0) // reserved
        writer.writeUInt16(estimatedRangeKm)
        writer.writeUInt16(consumptionMlPerKm)
        writer.writeUInt16(fuelRemainingMl)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
