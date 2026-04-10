import XCTest

@testable import BLEProtocol

final class StatusMessageTests: XCTestCase {
    private func roundTrip(_ message: StatusMessage) throws {
        let encoded = message.encode()
        let decoded = try StatusMessage.decode(encoded)
        XCTAssertEqual(decoded, message)
    }

    func test_screenChanged_roundTrip() throws {
        try roundTrip(.screenChanged(.navigation))
        try roundTrip(.screenChanged(.clock))
        try roundTrip(.screenChanged(.compass))
    }

    func test_screenChanged_encodedBytesAreFixedLayout() {
        let bytes = StatusMessage.screenChanged(.navigation).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x01, 0x01])
    }

    func test_screenChanged_clock_encodedBytesAreFixedLayout() {
        let bytes = StatusMessage.screenChanged(.clock).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x01, 0x0D])
    }

    func test_decode_unknownStatusType_isRejected() {
        let bytes = Data([0x01, 0xFF, 0x01])
        XCTAssertThrowsError(try StatusMessage.decode(bytes)) { error in
            guard case BLEProtocolError.unknownStatusType(let raw) = error else {
                return XCTFail("expected unknownStatusType, got \(error)")
            }
            XCTAssertEqual(raw, 0xFF)
        }
    }

    func test_decode_unknownScreenId_isRejected() {
        let bytes = Data([0x01, 0x01, 0xEE])
        XCTAssertThrowsError(try StatusMessage.decode(bytes)) { error in
            guard case BLEProtocolError.unknownScreenId = error else {
                return XCTFail("expected unknownScreenId, got \(error)")
            }
        }
    }

    func test_decode_truncated_isRejected() {
        let bytes = Data([0x01, 0x01])
        XCTAssertThrowsError(try StatusMessage.decode(bytes)) { error in
            guard case BLEProtocolError.truncatedHeader = error else {
                return XCTFail("expected truncatedHeader, got \(error)")
            }
        }
    }

    func test_decode_unsupportedVersion_isRejected() {
        let bytes = Data([0x02, 0x01, 0x01])
        XCTAssertThrowsError(try StatusMessage.decode(bytes)) { error in
            guard case BLEProtocolError.unsupportedVersion(let v) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(v, 0x02)
        }
    }
}
