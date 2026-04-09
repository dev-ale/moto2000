import XCTest

@testable import BLEProtocol

final class CompassDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let data = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: CompassData.trueHeadingUnknown,
            headingAccuracyDegX10: 20,
            flags: 0
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, CompassData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        // magnetic=0x0102=258, true=0x0304=772, accuracy=0x0020=32, flags=0x01,
        // reserved=0x00.
        let data = CompassData(
            magneticHeadingDegX10: 0x0102,
            trueHeadingDegX10: 0x0304,
            headingAccuracyDegX10: 0x0020,
            flags: CompassData.useTrueHeadingFlag
        )
        let bytes = try data.encode()
        XCTAssertEqual(
            Array(bytes),
            [0x02, 0x01, 0x04, 0x03, 0x20, 0x00, 0x01, 0x00]
        )
    }

    func test_encodeDecode_roundTrip_magnetic() throws {
        let original = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: CompassData.trueHeadingUnknown,
            headingAccuracyDegX10: 20,
            flags: 0
        )
        let bytes = try original.encode()
        let decoded = try CompassData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertFalse(decoded.useTrueHeading)
    }

    func test_encodeDecode_roundTrip_true() throws {
        let original = CompassData(
            magneticHeadingDegX10: 885,
            trueHeadingDegX10: 900,
            headingAccuracyDegX10: 15,
            flags: CompassData.useTrueHeadingFlag
        )
        let bytes = try original.encode()
        let decoded = try CompassData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.useTrueHeading)
    }

    func test_encode_rejectsOutOfRangeMagnetic() {
        let data = CompassData(
            magneticHeadingDegX10: 3600,
            trueHeadingDegX10: 0,
            headingAccuracyDegX10: 0,
            flags: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "compass.magneticHeadingDegX10")
            )
        }
    }

    func test_encode_rejectsOutOfRangeTrueButAllowsUnknown() throws {
        let bad = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: 3600,
            headingAccuracyDegX10: 0,
            flags: 0
        )
        XCTAssertThrowsError(try bad.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "compass.trueHeadingDegX10")
            )
        }
        // 0xFFFF is the unknown sentinel and must pass.
        let unknownTrue = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: CompassData.trueHeadingUnknown,
            headingAccuracyDegX10: 0,
            flags: 0
        )
        _ = try unknownTrue.encode()
    }

    func test_encode_rejectsOutOfRangeAccuracy() {
        let data = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: 0,
            headingAccuracyDegX10: 3600,
            flags: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "compass.headingAccuracyDegX10")
            )
        }
    }

    func test_encode_rejectsReservedFlagBits() {
        let data = CompassData(
            magneticHeadingDegX10: 0,
            trueHeadingDegX10: 0,
            headingAccuracyDegX10: 0,
            flags: 0b0000_0010
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "compass.flags")
            )
        }
    }

    func test_decode_rejectsReservedByte() {
        var bytes = Data(repeating: 0, count: CompassData.encodedSize)
        bytes[7] = 0xAA
        XCTAssertThrowsError(try CompassData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "compass.reserved")
            )
        }
    }

    func test_decode_rejectsReservedFlagBits() {
        var bytes = Data(repeating: 0, count: CompassData.encodedSize)
        bytes[6] = 0b1000_0000
        XCTAssertThrowsError(try CompassData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "compass.flags")
            )
        }
    }

    func test_decode_rejectsOutOfRangeMagnetic() {
        // 3600 = 0x0E10 -> little-endian bytes 0x10 0x0E.
        var bytes = Data(repeating: 0, count: CompassData.encodedSize)
        bytes[0] = 0x10
        bytes[1] = 0x0E
        XCTAssertThrowsError(try CompassData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "compass.magneticHeadingDegX10")
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try CompassData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .compass)
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_screenID_expectedBodySizeIsCompass() {
        XCTAssertEqual(ScreenID.compass.expectedBodySize, CompassData.encodedSize)
    }

    func test_screenPayloadCodec_roundTrip() throws {
        let data = CompassData(
            magneticHeadingDegX10: 2250,
            trueHeadingDegX10: CompassData.trueHeadingUnknown,
            headingAccuracyDegX10: 30,
            flags: 0
        )
        let payload = ScreenPayload.compass(data, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        XCTAssertEqual(bytes.count, 8 + CompassData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
    }

    func test_screenPayloadCodec_decode_compassTrueHeading() throws {
        let data = CompassData(
            magneticHeadingDegX10: 885,
            trueHeadingDegX10: 900,
            headingAccuracyDegX10: 15,
            flags: CompassData.useTrueHeadingFlag
        )
        let payload = ScreenPayload.compass(data, flags: [.nightMode])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.screenID, .compass)
        XCTAssertEqual(decoded.flags, [.nightMode])
    }
}
