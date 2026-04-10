import XCTest

@testable import BLEProtocol

final class BlitzerDataTests: XCTestCase {
    private func sample(_ type: BlitzerData.CameraTypeWire = .fixed) -> BlitzerData {
        BlitzerData(
            distanceMeters: 500,
            speedLimitKmh: 80,
            currentSpeedKmhX10: 720,
            cameraType: type
        )
    }

    // MARK: - Round-trip

    func test_encodeDecode_roundTrip_fixed() throws {
        let original = sample(.fixed)
        let bytes = try original.encode()
        XCTAssertEqual(bytes.count, BlitzerData.encodedSize)
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_mobile() throws {
        let original = sample(.mobile)
        let bytes = try original.encode()
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_redLight() throws {
        let original = sample(.redLight)
        let bytes = try original.encode()
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_section() throws {
        let original = sample(.section)
        let bytes = try original.encode()
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_unknown() throws {
        let original = sample(.unknown)
        let bytes = try original.encode()
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_unknownSpeedLimit() throws {
        let original = BlitzerData(
            distanceMeters: 200,
            speedLimitKmh: BlitzerData.unknownSpeedLimit,
            currentSpeedKmhX10: 900,
            cameraType: .unknown
        )
        let bytes = try original.encode()
        let decoded = try BlitzerData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.speedLimitKmh, 0xFFFF)
    }

    // MARK: - Payload round-trip through ScreenPayloadCodec

    func test_fullPayload_roundTrip_withAlert() throws {
        let blitzer = sample(.fixed)
        let payload = ScreenPayload.blitzer(blitzer, flags: [.alert])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        guard case .blitzer(_, let flags) = decoded else {
            XCTFail("expected blitzer"); return
        }
        XCTAssertTrue(flags.contains(.alert))
    }

    func test_fullPayload_roundTrip_noAlert() throws {
        let blitzer = sample(.mobile)
        let payload = ScreenPayload.blitzer(blitzer, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        guard case .blitzer(_, let flags) = decoded else {
            XCTFail("expected blitzer"); return
        }
        XCTAssertFalse(flags.contains(.alert))
    }

    // MARK: - Range validation

    func test_decode_wrongBodySize_throws() {
        let tooShort = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try BlitzerData.decode(tooShort)) { error in
            guard case BLEProtocolError.bodyLengthMismatch(let screen, let expected, let actual) = error else {
                XCTFail("unexpected error: \(error)"); return
            }
            XCTAssertEqual(screen, .blitzer)
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_decode_unknownCameraType_throws() {
        var body = Data(repeating: 0, count: 8)
        body[6] = 0xFF // unknown camera type
        XCTAssertThrowsError(try BlitzerData.decode(body)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "blitzer.camera_type"))
        }
    }

    func test_decode_nonZeroReserved_throws() {
        var body = Data(repeating: 0, count: 8)
        body[6] = 0x00 // fixed camera
        body[7] = 0x01 // non-zero reserved
        XCTAssertThrowsError(try BlitzerData.decode(body)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .nonZeroBodyReserved(field: "blitzer.reserved"))
        }
    }

    // MARK: - Camera type enum coverage

    func test_cameraTypeWire_allValues() {
        XCTAssertEqual(BlitzerData.CameraTypeWire.fixed.rawValue, 0x00)
        XCTAssertEqual(BlitzerData.CameraTypeWire.mobile.rawValue, 0x01)
        XCTAssertEqual(BlitzerData.CameraTypeWire.redLight.rawValue, 0x02)
        XCTAssertEqual(BlitzerData.CameraTypeWire.section.rawValue, 0x03)
        XCTAssertEqual(BlitzerData.CameraTypeWire.unknown.rawValue, 0x04)
    }
}
