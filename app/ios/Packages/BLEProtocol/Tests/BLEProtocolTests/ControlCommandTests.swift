import XCTest

@testable import BLEProtocol

final class ControlCommandTests: XCTestCase {
    private func roundTrip(_ command: ControlCommand) throws {
        let encoded = command.encode()
        if case .setScreenOrder = command {
            // Variable-length: version + cmd + count + screen_ids
        } else {
            XCTAssertEqual(encoded.count, ControlCommand.encodedSize)
        }
        let decoded = try ControlCommand.decode(encoded)
        XCTAssertEqual(decoded, command)
    }

    func test_setActiveScreen_roundTrip() throws {
        try roundTrip(.setActiveScreen(.clock))
        try roundTrip(.setActiveScreen(.compass))
        try roundTrip(.setActiveScreen(.navigation))
        try roundTrip(.setActiveScreen(.speedHeading))
    }

    func test_setBrightness_roundTrip() throws {
        try roundTrip(.setBrightness(0))
        try roundTrip(.setBrightness(50))
        try roundTrip(.setBrightness(100))
    }

    func test_sleepWakeClear_roundTrip() throws {
        try roundTrip(.sleep)
        try roundTrip(.wake)
        try roundTrip(.clearAlertOverlay)
    }

    func test_checkForOTAUpdate_roundTrip() throws {
        try roundTrip(.checkForOTAUpdate)
    }

    func test_setScreenOrder_roundTrip() throws {
        try roundTrip(.setScreenOrder([.navigation, .compass, .clock]))
        try roundTrip(.setScreenOrder([]))
        try roundTrip(.setScreenOrder([.speedHeading]))
    }

    func test_setScreenOrder_encodedBytesAreCorrectLayout() {
        let bytes = ControlCommand.setScreenOrder([.navigation, .compass, .clock]).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x07, 0x03, 0x01, 0x03, 0x0D])
    }

    func test_setScreenOrder_empty_encodedBytesAreCorrectLayout() {
        let bytes = ControlCommand.setScreenOrder([]).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x07, 0x00])
    }

    func test_checkForOTAUpdate_encodedBytesAreFixedLayout() {
        let bytes = ControlCommand.checkForOTAUpdate.encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x06, 0x00, 0x00])
    }

    func test_checkForOTAUpdate_withNonZeroValue_isRejected() {
        let bytes = Data([0x01, 0x06, 0x01, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.invalidReserved = error else {
                return XCTFail("expected invalidReserved, got \(error)")
            }
        }
    }

    func test_setActiveScreen_encodedBytesAreFixedLayout() {
        let bytes = ControlCommand.setActiveScreen(.clock).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x01, 0x0D, 0x00])
    }

    func test_setBrightness_encodedBytesAreFixedLayout() {
        let bytes = ControlCommand.setBrightness(75).encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x02, 75, 0x00])
    }

    func test_sleep_encodedBytesAreFixedLayout() {
        let bytes = ControlCommand.sleep.encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x03, 0x00, 0x00])
    }

    func test_decode_unknownCommand_isRejected() {
        let bytes = Data([0x01, 0xFF, 0x00, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.unknownCommand(let raw) = error else {
                return XCTFail("expected unknownCommand, got \(error)")
            }
            XCTAssertEqual(raw, 0xFF)
        }
    }

    func test_decode_unknownScreenId_isRejected() {
        let bytes = Data([0x01, 0x01, 0xEE, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.unknownScreenId = error else {
                return XCTFail("expected unknownScreenId, got \(error)")
            }
        }
    }

    func test_decode_brightnessOver100_isRejected() {
        let bytes = Data([0x01, 0x02, 101, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.invalidCommandValue(let field) = error else {
                return XCTFail("expected invalidCommandValue, got \(error)")
            }
            XCTAssertEqual(field, "brightness")
        }
    }

    func test_decode_truncated_isRejected() {
        let bytes = Data([0x01, 0x01, 0x0D])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.truncatedHeader = error else {
                return XCTFail("expected truncatedHeader, got \(error)")
            }
        }
    }

    func test_decode_unsupportedVersion_isRejected() {
        let bytes = Data([0x02, 0x01, 0x0D, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.unsupportedVersion(let v) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(v, 0x02)
        }
    }

    func test_decode_sleepWithNonZeroValue_isRejected() {
        let bytes = Data([0x01, 0x03, 0x05, 0x00])
        XCTAssertThrowsError(try ControlCommand.decode(bytes)) { error in
            guard case BLEProtocolError.invalidReserved = error else {
                return XCTFail("expected invalidReserved, got \(error)")
            }
        }
    }

    func test_setBrightness_outOfRangeOnEncodeIsCallerResponsibility() {
        // Encode is intentionally non-throwing — the API requires callers to
        // pre-validate. The ScreenController in ScramCore validates 0...100
        // before constructing this case. The decode path enforces the limit
        // for incoming bytes, which is the only place untrusted data lands.
        let bytes = ControlCommand.setBrightness(200).encode()
        XCTAssertEqual(bytes[2], 200)
    }
}
