import XCTest

@testable import BLEProtocol

final class LeanAngleDataTests: XCTestCase {
    func test_encodedSize_isEightBytes() {
        XCTAssertEqual(LeanAngleData.encodedSize, 8)
    }

    func test_encode_matchesExpectedSize() throws {
        let data = LeanAngleData(
            currentLeanDegX10: 0,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 0,
            confidencePercent: 100
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, LeanAngleData.encodedSize)
    }

    func test_encode_littleEndianLayout_positiveCurrent() throws {
        // current=250 (25.0° right), maxLeft=150, maxRight=400, conf=95
        let data = LeanAngleData(
            currentLeanDegX10: 250,
            maxLeftLeanDegX10: 150,
            maxRightLeanDegX10: 400,
            confidencePercent: 95
        )
        let bytes = try data.encode()
        XCTAssertEqual(
            Array(bytes),
            [0xFA, 0x00, 0x96, 0x00, 0x90, 0x01, 0x5F, 0x00]
        )
    }

    func test_encode_littleEndianLayout_negativeCurrent() throws {
        // current=-425 (42.5° left). Two's complement int16 = 0xFE57
        let data = LeanAngleData(
            currentLeanDegX10: -425,
            maxLeftLeanDegX10: 425,
            maxRightLeanDegX10: 180,
            confidencePercent: 90
        )
        let bytes = try data.encode()
        XCTAssertEqual(
            Array(bytes),
            [0x57, 0xFE, 0xA9, 0x01, 0xB4, 0x00, 0x5A, 0x00]
        )
    }

    func test_encodeDecode_roundTrip_upright() throws {
        let original = LeanAngleData(
            currentLeanDegX10: 0,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 0,
            confidencePercent: 100
        )
        let bytes = try original.encode()
        let decoded = try LeanAngleData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_negativeAndPositive() throws {
        for current: Int16 in [-900, -425, -1, 0, 1, 250, 900] {
            let original = LeanAngleData(
                currentLeanDegX10: current,
                maxLeftLeanDegX10: 600,
                maxRightLeanDegX10: 700,
                confidencePercent: 80
            )
            let bytes = try original.encode()
            let decoded = try LeanAngleData.decode(bytes)
            XCTAssertEqual(decoded, original, "round trip failed for current=\(current)")
        }
    }

    func test_encode_rejectsCurrentOverPositiveMax() {
        let data = LeanAngleData(
            currentLeanDegX10: 901,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 0,
            confidencePercent: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.currentLeanDegX10")
            )
        }
    }

    func test_encode_rejectsCurrentBelowNegativeMax() {
        let data = LeanAngleData(
            currentLeanDegX10: -901,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 0,
            confidencePercent: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.currentLeanDegX10")
            )
        }
    }

    func test_encode_rejectsMaxLeftOutOfRange() {
        let data = LeanAngleData(
            currentLeanDegX10: 0,
            maxLeftLeanDegX10: 901,
            maxRightLeanDegX10: 0,
            confidencePercent: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.maxLeftLeanDegX10")
            )
        }
    }

    func test_encode_rejectsMaxRightOutOfRange() {
        let data = LeanAngleData(
            currentLeanDegX10: 0,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 901,
            confidencePercent: 0
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.maxRightLeanDegX10")
            )
        }
    }

    func test_encode_rejectsConfidenceOver100() {
        let data = LeanAngleData(
            currentLeanDegX10: 0,
            maxLeftLeanDegX10: 0,
            maxRightLeanDegX10: 0,
            confidencePercent: 101
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.confidencePercent")
            )
        }
    }

    func test_decode_rejectsReservedByte() {
        var bytes = Data(repeating: 0, count: LeanAngleData.encodedSize)
        bytes[7] = 0xAA
        XCTAssertThrowsError(try LeanAngleData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "leanAngle.reserved")
            )
        }
    }

    func test_decode_rejectsCurrentOutOfRange() {
        // 1000 (>900) — little endian: 0xE8 0x03
        var bytes = Data(repeating: 0, count: LeanAngleData.encodedSize)
        bytes[0] = 0xE8
        bytes[1] = 0x03
        XCTAssertThrowsError(try LeanAngleData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.currentLeanDegX10")
            )
        }
    }

    func test_decode_rejectsConfidenceOver100() {
        var bytes = Data(repeating: 0, count: LeanAngleData.encodedSize)
        bytes[6] = 200
        XCTAssertThrowsError(try LeanAngleData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "leanAngle.confidencePercent")
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try LeanAngleData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .leanAngle)
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_screenID_expectedBodySizeIsLeanAngle() {
        XCTAssertEqual(ScreenID.leanAngle.expectedBodySize, LeanAngleData.encodedSize)
    }

    func test_screenPayloadCodec_roundTrip_leanAngle() throws {
        let data = LeanAngleData(
            currentLeanDegX10: -425,
            maxLeftLeanDegX10: 425,
            maxRightLeanDegX10: 180,
            confidencePercent: 90
        )
        let payload = ScreenPayload.leanAngle(data, flags: [.nightMode])
        let bytes = try ScreenPayloadCodec.encode(payload)
        XCTAssertEqual(bytes.count, 8 + LeanAngleData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.screenID, .leanAngle)
        XCTAssertEqual(decoded.flags, [.nightMode])
    }
}
