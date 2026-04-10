import XCTest

@testable import BLEProtocol

final class FuelDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let data = FuelData(
            tankPercent: 73,
            estimatedRangeKm: 200,
            consumptionMlPerKm: 38,
            fuelRemainingMl: 9500
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, FuelData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        // tank_percent=100, range=350(0x015E), consumption=38(0x0026),
        // remaining=13000(0x32C8)
        let data = FuelData(
            tankPercent: 100,
            estimatedRangeKm: 350,
            consumptionMlPerKm: 38,
            fuelRemainingMl: 13000
        )
        let bytes = try data.encode()
        let expected: [UInt8] = [
            0x64,        // tank_percent = 100
            0x00,        // reserved
            0x5E, 0x01,  // range 350 LE
            0x26, 0x00,  // consumption 38 LE
            0xC8, 0x32,  // remaining 13000 LE
        ]
        XCTAssertEqual(Array(bytes), expected)
    }

    func test_encodeDecode_roundTrip() throws {
        let original = FuelData(
            tankPercent: 50,
            estimatedRangeKm: 175,
            consumptionMlPerKm: 38,
            fuelRemainingMl: 6500
        )
        let bytes = try original.encode()
        let decoded = try FuelData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_unknownValues() throws {
        let original = FuelData(
            tankPercent: 0,
            estimatedRangeKm: FuelData.unknown,
            consumptionMlPerKm: FuelData.unknown,
            fuelRemainingMl: FuelData.unknown
        )
        let bytes = try original.encode()
        let decoded = try FuelData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsTankPercentOver100() {
        let data = FuelData(
            tankPercent: 101,
            estimatedRangeKm: 0,
            consumptionMlPerKm: 0,
            fuelRemainingMl: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "fuel.tank_percent")
            )
        }
    }

    func test_decode_rejectsTankPercentOver100() {
        var bytes = [UInt8](repeating: 0, count: FuelData.encodedSize)
        bytes[0] = 101
        XCTAssertThrowsError(try FuelData.decode(Data(bytes))) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "fuel.tank_percent")
            )
        }
    }

    func test_decode_rejectsNonZeroReserved() {
        var bytes = [UInt8](repeating: 0, count: FuelData.encodedSize)
        bytes[0] = 50
        bytes[1] = 1 // non-zero reserved
        XCTAssertThrowsError(try FuelData.decode(Data(bytes))) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "fuel.reserved")
            )
        }
    }

    func test_decode_rejectsWrongBodySize() {
        let tooShort = Data(repeating: 0, count: FuelData.encodedSize - 1)
        XCTAssertThrowsError(try FuelData.decode(tooShort)) { error in
            guard case let .bodyLengthMismatch(screen, expected, actual) = (error as? BLEProtocolError) else {
                XCTFail("expected bodyLengthMismatch, got \(error)")
                return
            }
            XCTAssertEqual(screen, .fuelEstimate)
            XCTAssertEqual(expected, FuelData.encodedSize)
            XCTAssertEqual(actual, FuelData.encodedSize - 1)
        }
    }

    func test_screenPayloadCodec_roundTripsFuel() throws {
        let original = ScreenPayload.fuelEstimate(
            FuelData(
                tankPercent: 73,
                estimatedRangeKm: 200,
                consumptionMlPerKm: 38,
                fuelRemainingMl: 9500
            ),
            flags: [.nightMode]
        )
        let encoded = try ScreenPayloadCodec.encode(original)
        // header (8) + body (8)
        XCTAssertEqual(encoded.count, 8 + FuelData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.screenID, .fuelEstimate)
    }

    func test_encode_boundaryValues() throws {
        // tank_percent = 0 and 100 should both be valid
        let zero = FuelData(tankPercent: 0, estimatedRangeKm: 0, consumptionMlPerKm: 0, fuelRemainingMl: 0)
        let _ = try zero.encode()

        let full = FuelData(tankPercent: 100, estimatedRangeKm: 0xFFFE, consumptionMlPerKm: 0xFFFE, fuelRemainingMl: 0xFFFE)
        let _ = try full.encode()
    }
}
