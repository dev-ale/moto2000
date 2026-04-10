import XCTest

@testable import BLEProtocol

final class IncomingCallDataTests: XCTestCase {
    private func sample(_ state: IncomingCallData.CallStateWire = .incoming) -> IncomingCallData {
        IncomingCallData(
            callState: state,
            callerHandle: "contact-mom"
        )
    }

    // MARK: - Round-trip

    func test_encodeDecode_roundTrip_incoming() throws {
        let original = sample(.incoming)
        let bytes = try original.encode()
        XCTAssertEqual(bytes.count, IncomingCallData.encodedSize)
        let decoded = try IncomingCallData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_connected() throws {
        let original = sample(.connected)
        let bytes = try original.encode()
        let decoded = try IncomingCallData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_ended() throws {
        let original = sample(.ended)
        let bytes = try original.encode()
        let decoded = try IncomingCallData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_emptyHandle() throws {
        let original = IncomingCallData(callState: .incoming, callerHandle: "")
        let bytes = try original.encode()
        let decoded = try IncomingCallData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Payload round-trip through ScreenPayloadCodec

    func test_fullPayload_roundTrip_incoming_withAlert() throws {
        let call = sample(.incoming)
        let payload = ScreenPayload.incomingCall(call, flags: [.alert])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        guard case .incomingCall(_, let flags) = decoded else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertTrue(flags.contains(.alert))
    }

    func test_fullPayload_roundTrip_connected_withAlert() throws {
        let call = sample(.connected)
        let payload = ScreenPayload.incomingCall(call, flags: [.alert])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
    }

    func test_fullPayload_roundTrip_ended_noAlert() throws {
        let call = sample(.ended)
        let payload = ScreenPayload.incomingCall(call, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        guard case .incomingCall(_, let flags) = decoded else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertFalse(flags.contains(.alert))
    }

    // MARK: - shouldSetAlertFlag

    func test_shouldSetAlertFlag_incoming() {
        XCTAssertTrue(sample(.incoming).shouldSetAlertFlag)
    }

    func test_shouldSetAlertFlag_connected() {
        XCTAssertTrue(sample(.connected).shouldSetAlertFlag)
    }

    func test_shouldSetAlertFlag_ended() {
        XCTAssertFalse(sample(.ended).shouldSetAlertFlag)
    }

    func test_recommendedFlags_incoming() {
        XCTAssertEqual(sample(.incoming).recommendedFlags, [.alert])
    }

    func test_recommendedFlags_ended() {
        XCTAssertEqual(sample(.ended).recommendedFlags, [])
    }

    // MARK: - Range validation

    func test_decode_wrongBodySize_throws() {
        let tooShort = Data(repeating: 0, count: 16)
        XCTAssertThrowsError(try IncomingCallData.decode(tooShort)) { error in
            guard case BLEProtocolError.bodyLengthMismatch(let screen, let expected, let actual) = error else {
                XCTFail("unexpected error: \(error)"); return
            }
            XCTAssertEqual(screen, .incomingCall)
            XCTAssertEqual(expected, 32)
            XCTAssertEqual(actual, 16)
        }
    }

    func test_decode_unknownCallState_throws() {
        var body = Data(repeating: 0, count: 32)
        body[0] = 0xFF // unknown state
        XCTAssertThrowsError(try IncomingCallData.decode(body)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "call.call_state"))
        }
    }

    func test_decode_nonZeroReserved_throws() {
        var body = Data(repeating: 0, count: 32)
        body[0] = 0x00 // incoming
        body[1] = 0x01 // non-zero reserved
        XCTAssertThrowsError(try IncomingCallData.decode(body)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .nonZeroBodyReserved(field: "call.reserved"))
        }
    }

    // MARK: - Caller handle encoding

    func test_callerHandle_maxLength() throws {
        // 29 bytes of text + 1 null terminator = 30 byte field
        let handle = String(repeating: "A", count: 29)
        let call = IncomingCallData(callState: .incoming, callerHandle: handle)
        let bytes = try call.encode()
        let decoded = try IncomingCallData.decode(bytes)
        XCTAssertEqual(decoded.callerHandle, handle)
    }

    // MARK: - All 3 call states enum coverage

    func test_callStateWire_allValues() {
        XCTAssertEqual(IncomingCallData.CallStateWire.incoming.rawValue, 0x00)
        XCTAssertEqual(IncomingCallData.CallStateWire.connected.rawValue, 0x01)
        XCTAssertEqual(IncomingCallData.CallStateWire.ended.rawValue, 0x02)
    }
}
