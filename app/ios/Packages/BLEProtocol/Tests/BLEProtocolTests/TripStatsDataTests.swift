import XCTest

@testable import BLEProtocol

final class TripStatsDataTests: XCTestCase {
    func test_encodedSize_is16() {
        XCTAssertEqual(TripStatsData.encodedSize, 16)
    }

    func test_encode_matchesExpectedSize() throws {
        let data = TripStatsData(
            rideTimeSeconds: 600,
            distanceMeters: 7_000,
            averageSpeedKmhX10: 420,
            maxSpeedKmhX10: 680,
            ascentMeters: 120,
            descentMeters: 120
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, TripStatsData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        // ride=0x01020304, distance=0x05060708, avg=0x0102, max=0x0203,
        // ascent=0x0405, descent=0x0607.
        let data = TripStatsData(
            rideTimeSeconds: 0x01020304,
            distanceMeters: 0x05060708,
            averageSpeedKmhX10: 0x0102,
            maxSpeedKmhX10: 0x0203,
            ascentMeters: 0x0405,
            descentMeters: 0x0607
        )
        let bytes = try data.encode()
        XCTAssertEqual(
            Array(bytes),
            [
                0x04, 0x03, 0x02, 0x01,
                0x08, 0x07, 0x06, 0x05,
                0x02, 0x01,
                0x03, 0x02,
                0x05, 0x04,
                0x07, 0x06,
            ]
        )
    }

    func test_encodeDecode_roundTrip() throws {
        let original = TripStatsData(
            rideTimeSeconds: 2_700,
            distanceMeters: 90_000,
            averageSpeedKmhX10: 1_200,
            maxSpeedKmhX10: 1_350,
            ascentMeters: 300,
            descentMeters: 280
        )
        let bytes = try original.encode()
        let decoded = try TripStatsData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_zerosRoundTrip() throws {
        let original = TripStatsData(
            rideTimeSeconds: 0,
            distanceMeters: 0,
            averageSpeedKmhX10: 0,
            maxSpeedKmhX10: 0,
            ascentMeters: 0,
            descentMeters: 0
        )
        let bytes = try original.encode()
        let decoded = try TripStatsData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsOutOfRangeAverageSpeed() {
        let data = TripStatsData(
            rideTimeSeconds: 0,
            distanceMeters: 0,
            averageSpeedKmhX10: 3_001,
            maxSpeedKmhX10: 0,
            ascentMeters: 0,
            descentMeters: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "tripStats.averageSpeedKmhX10")
            )
        }
    }

    func test_encode_rejectsOutOfRangeMaxSpeed() {
        let data = TripStatsData(
            rideTimeSeconds: 0,
            distanceMeters: 0,
            averageSpeedKmhX10: 0,
            maxSpeedKmhX10: 5_000,
            ascentMeters: 0,
            descentMeters: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "tripStats.maxSpeedKmhX10")
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 8)
        XCTAssertThrowsError(try TripStatsData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .tripStats)
            XCTAssertEqual(expected, 16)
            XCTAssertEqual(actual, 8)
        }
    }

    func test_screenPayloadCodec_roundTrip() throws {
        let data = TripStatsData(
            rideTimeSeconds: 5_064,
            distanceMeters: 90_000,
            averageSpeedKmhX10: 1_200,
            maxSpeedKmhX10: 1_350,
            ascentMeters: 300,
            descentMeters: 280
        )
        let payload = ScreenPayload.tripStats(data, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        XCTAssertEqual(bytes.count, BLEProtocolConstants.headerSize + TripStatsData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
    }

    func test_expectedBodySize_isRegistered() {
        XCTAssertEqual(ScreenID.tripStats.expectedBodySize, TripStatsData.encodedSize)
    }
}
