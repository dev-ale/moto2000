import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class CallAlertServiceTests: XCTestCase {
    func test_encode_incoming_setsAlertFlag() throws {
        let observer = MockCallObserver()
        let service = CallAlertService(observer: observer)

        let event = CallEvent(scenarioTime: 0, state: .incoming, callerHandle: "contact-mom")
        let data = service.encode(event)
        XCTAssertNotNil(data)
        let payload = try ScreenPayloadCodec.decode(data!)
        guard case .incomingCall(let call, let flags) = payload else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertEqual(call.callState, .incoming)
        XCTAssertEqual(call.callerHandle, "contact-mom")
        XCTAssertTrue(flags.contains(.alert), "ALERT flag must be set for incoming")
    }

    func test_encode_connected_setsAlertFlag() throws {
        let observer = MockCallObserver()
        let service = CallAlertService(observer: observer)

        let event = CallEvent(scenarioTime: 0, state: .connected, callerHandle: "contact-mom")
        let data = service.encode(event)
        XCTAssertNotNil(data)
        let payload = try ScreenPayloadCodec.decode(data!)
        guard case .incomingCall(_, let flags) = payload else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertTrue(flags.contains(.alert), "ALERT flag must be set for connected")
    }

    func test_encode_ended_clearsAlertFlag() throws {
        let observer = MockCallObserver()
        let service = CallAlertService(observer: observer)

        let event = CallEvent(scenarioTime: 0, state: .ended, callerHandle: "contact-mom")
        let data = service.encode(event)
        XCTAssertNotNil(data)
        let payload = try ScreenPayloadCodec.decode(data!)
        guard case .incomingCall(_, let flags) = payload else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertFalse(flags.contains(.alert), "ALERT flag must NOT be set for ended")
    }

    func test_encode_roundTrips_allStates() throws {
        let observer = MockCallObserver()
        let service = CallAlertService(observer: observer)

        for state: CallState in [.incoming, .connected, .ended] {
            let event = CallEvent(scenarioTime: 0, state: state, callerHandle: "test")
            let data = service.encode(event)
            XCTAssertNotNil(data, "encode should not return nil for \(state)")
            let payload = try ScreenPayloadCodec.decode(data!)
            let reencoded = try ScreenPayloadCodec.encode(payload)
            XCTAssertEqual(data, reencoded, "round-trip mismatch for \(state)")
        }
    }

    func test_truncateUTF8_shortString() {
        XCTAssertEqual(CallAlertService.truncateUTF8("hello", maxByteCount: 29), "hello")
    }

    func test_truncateUTF8_longString() {
        let long = String(repeating: "X", count: 40)
        let result = CallAlertService.truncateUTF8(long, maxByteCount: 29)
        XCTAssertEqual(result.utf8.count, 29)
    }

    func test_service_emitsPayloadsOnStream() async throws {
        let observer = MockCallObserver()
        let service = CallAlertService(observer: observer)
        service.start()

        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.encodedPayloads {
                out.append(blob)
                if out.count >= 2 { return out }
            }
            return out
        }

        observer.emit(CallEvent(scenarioTime: 1, state: .incoming, callerHandle: "mom"))
        observer.emit(CallEvent(scenarioTime: 2, state: .ended, callerHandle: "mom"))

        try await Task.sleep(nanoseconds: 100_000_000)
        await observer.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, 2)

        // First payload: incoming with ALERT
        let p1 = try ScreenPayloadCodec.decode(received[0])
        guard case .incomingCall(_, let f1) = p1 else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertTrue(f1.contains(.alert))

        // Second payload: ended without ALERT
        let p2 = try ScreenPayloadCodec.decode(received[1])
        guard case .incomingCall(_, let f2) = p2 else {
            XCTFail("expected incomingCall"); return
        }
        XCTAssertFalse(f2.contains(.alert))
    }
}
