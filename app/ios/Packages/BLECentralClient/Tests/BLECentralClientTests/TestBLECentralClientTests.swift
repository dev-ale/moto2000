import Foundation
import XCTest
@testable import BLECentralClient

final class TestBLECentralClientTests: XCTestCase {
    func testInitialStateIsIdle() async {
        let client = TestBLECentralClient()
        let state = await client.currentState()
        XCTAssertEqual(state, .idle)
    }

    func testConnectFromIdleMovesToScanning() async {
        let client = TestBLECentralClient()
        await client.connect()
        let state = await client.currentState()
        XCTAssertEqual(state, .scanning)
        let count = await client.connectCallCount
        XCTAssertEqual(count, 1)
    }

    func testConnectIsIdempotentWhileBusy() async {
        let client = TestBLECentralClient()
        await client.simulateConnected()
        await client.connect()
        let state = await client.currentState()
        XCTAssertEqual(state, .connected)
        let count = await client.connectCallCount
        XCTAssertEqual(count, 1)
    }

    func testSendWhileDisconnectedThrows() async {
        let client = TestBLECentralClient()
        do {
            try await client.send(Data([0x01]))
            XCTFail("expected throw")
        } catch let error as BLECentralClientError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendWhileConnectedRecordsPayload() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()
        try await client.send(Data([0x01, 0x02]))
        try await client.send(Data([0x03]))
        let writes = await client.writes
        XCTAssertEqual(writes, [Data([0x01, 0x02]), Data([0x03])])
    }

    func testNextSendErrorIsConsumedOnce() async {
        let client = TestBLECentralClient()
        await client.simulateConnected()
        await client.setNextSendError(.writeFailed(message: "boom"))
        do {
            try await client.send(Data([0x01]))
            XCTFail("expected throw")
        } catch let err as BLECentralClientError {
            XCTAssertEqual(err, .writeFailed(message: "boom"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // After consumption the next write should succeed.
        do {
            try await client.send(Data([0x02]))
        } catch {
            XCTFail("unexpected throw: \(error)")
        }
        let writes = await client.writes
        XCTAssertEqual(writes, [Data([0x02])])
    }

    func testDisconnectRecordsCountAndTerminalState() async {
        let client = TestBLECentralClient()
        await client.simulateConnected()
        await client.disconnect()
        let state = await client.currentState()
        XCTAssertEqual(state, .disconnected(reason: .userInitiated))
        let count = await client.disconnectCallCount
        XCTAssertEqual(count, 1)
    }

    func testSimulateHelpersDriveStateTransitions() async {
        let client = TestBLECentralClient()
        await client.simulateConnecting()
        var s = await client.currentState()
        XCTAssertEqual(s, .connecting)
        await client.simulateConnected()
        s = await client.currentState()
        XCTAssertEqual(s, .connected)
        await client.simulateReconnecting(attempt: 2)
        s = await client.currentState()
        XCTAssertEqual(s, .reconnecting(attempt: 2))
        await client.simulateDisconnect(reason: .linkLost)
        s = await client.currentState()
        XCTAssertEqual(s, .disconnected(reason: .linkLost))
        await client.forceState(.idle)
        s = await client.currentState()
        XCTAssertEqual(s, .idle)
    }

    func testStateStreamYieldsInitialAndTransitions() async {
        let client = TestBLECentralClient()
        let stream = client.stateStream
        await client.simulateConnecting()
        await client.simulateConnected()
        await client.simulateDisconnect(reason: .linkLost)

        var collected: [ConnectionState] = []
        for await state in stream {
            collected.append(state)
            if collected.count == 4 { break }
        }
        XCTAssertEqual(collected.first, .idle)
        XCTAssertTrue(collected.contains(.connecting))
        XCTAssertTrue(collected.contains(.connected))
        XCTAssertTrue(collected.contains(.disconnected(reason: .linkLost)))
    }

    func testCoreBluetoothStubBehavesAsDocumented() async throws {
        let client = CoreBluetoothCentralClient()
        var s = await client.currentState()
        XCTAssertEqual(s, .idle)
        await client.connect()
        s = await client.currentState()
        XCTAssertEqual(s, .scanning)
        // Second connect from non-idle is a no-op.
        await client.connect()
        s = await client.currentState()
        XCTAssertEqual(s, .scanning)
        // Send while disconnected throws.
        do {
            try await client.send(Data([0x01]))
            XCTFail("expected throw")
        } catch let err as BLECentralClientError {
            XCTAssertEqual(err, .notConnected)
        }
        await client.disconnect()
        s = await client.currentState()
        XCTAssertEqual(s, .disconnected(reason: .userInitiated))
    }
}
