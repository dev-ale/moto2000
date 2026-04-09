import XCTest

@testable import BLEProtocol

final class SpeedHeadingDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let data = SpeedHeadingData(
            speedKmhX10: 453,
            headingDegX10: 1200,
            altitudeMeters: 260,
            temperatureCelsiusX10: 140
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, SpeedHeadingData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        // speed=0x0102=258, heading=0x0304=772 (77.2°), altitude=0x0506=1286,
        // temperature=0x00C8=200 (20.0°C) — all in range.
        let data = SpeedHeadingData(
            speedKmhX10: 0x0102,
            headingDegX10: 0x0304,
            altitudeMeters: 0x0506,
            temperatureCelsiusX10: 0x00C8
        )
        let bytes = try data.encode()
        XCTAssertEqual(Array(bytes), [0x02, 0x01, 0x04, 0x03, 0x06, 0x05, 0xC8, 0x00])
    }

    func test_encodeDecode_roundTrip() throws {
        let original = SpeedHeadingData(
            speedKmhX10: 1200,
            headingDegX10: 450,
            altitudeMeters: 500,
            temperatureCelsiusX10: 220
        )
        let bytes = try original.encode()
        let decoded = try SpeedHeadingData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_negatives() throws {
        let original = SpeedHeadingData(
            speedKmhX10: 0,
            headingDegX10: 0,
            altitudeMeters: -100,
            temperatureCelsiusX10: -150
        )
        let bytes = try original.encode()
        let decoded = try SpeedHeadingData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsOutOfRangeSpeed() {
        let data = SpeedHeadingData(
            speedKmhX10: 3001,
            headingDegX10: 0,
            altitudeMeters: 0,
            temperatureCelsiusX10: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "speedHeading.speedKmhX10")
            )
        }
    }

    func test_encode_rejectsOutOfRangeHeading() {
        let data = SpeedHeadingData(
            speedKmhX10: 0,
            headingDegX10: 3600,
            altitudeMeters: 0,
            temperatureCelsiusX10: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "speedHeading.headingDegX10")
            )
        }
    }

    func test_encode_rejectsOutOfRangeAltitude() {
        let data = SpeedHeadingData(
            speedKmhX10: 0,
            headingDegX10: 0,
            altitudeMeters: 9001,
            temperatureCelsiusX10: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "speedHeading.altitudeMeters")
            )
        }
    }

    func test_encode_rejectsOutOfRangeTemperature() {
        let data = SpeedHeadingData(
            speedKmhX10: 0,
            headingDegX10: 0,
            altitudeMeters: 0,
            temperatureCelsiusX10: 601
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "speedHeading.temperatureCelsiusX10")
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try SpeedHeadingData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .speedHeading)
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_screenPayloadCodec_roundTrip() throws {
        let data = SpeedHeadingData(
            speedKmhX10: 453,
            headingDegX10: 1200,
            altitudeMeters: 260,
            temperatureCelsiusX10: 140
        )
        let payload = ScreenPayload.speedHeading(data, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
    }
}
