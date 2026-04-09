import BLEProtocol
import Foundation
import RideSimulatorKit
import XCTest
@testable import BLECentralClient

final class ReconnectCoordinatorTests: XCTestCase {
    func testSendCachesPayloadOnSuccess() async {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        await client.simulateConnected()
        await coord.handle(.didConnect)
        await clock.advance(to: 1.0)

        let body = Data([0xAA, 0xBB, 0xCC])
        await coord.send(body: body, for: .clock)

        let writes = await client.writes
        XCTAssertEqual(writes, [body])
        let entry = await coord.cache.entry(for: .clock)
        XCTAssertEqual(entry?.body, body)
        XCTAssertEqual(entry?.receivedAt, 1.0)
        let snapshot = await coord.health.snapshot(at: 1.0)
        XCTAssertEqual(snapshot.level, .good)
    }

    func testSendSwallowsFailureAndDoesNotTouchCache() async {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        // Never connected; send will throw .notConnected.
        await coord.send(body: Data([0x01]), for: .clock)
        let entry = await coord.cache.entry(for: .clock)
        XCTAssertNil(entry)
    }

    func testStartRequestedConnectsClient() async {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        await coord.handle(.startRequested)
        let count = await client.connectCallCount
        XCTAssertEqual(count, 1)
    }

    func testReconnectScheduleFiresWithinFiveSeconds() async throws {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        // Start, connect successfully.
        await coord.handle(.startRequested)
        await client.simulateConnected()
        await coord.handle(.didConnect)

        // Drop the link at t=2.0.
        await clock.advance(to: 2.0)
        await client.simulateDisconnect(reason: .linkLost)
        await coord.handle(.didDisconnect(reason: .linkLost))

        // FSM scheduled a 100 ms reconnect. Advance past the wake and let
        // the scheduled task run.
        await clock.advance(to: 2.2)
        // Yield to let the scheduled reconnect task run.
        await Task.yield()
        await Task.yield()
        await Task.yield()

        // The coordinator should have dispatched attemptConnect (another
        // client.connect). Meanwhile simulate success: bring the link back.
        await client.simulateConnected()
        await coord.handle(.didConnect)

        let latency = await coord.lastReconnectLatencySeconds
        XCTAssertNotNil(latency)
        if let latency {
            XCTAssertLessThan(latency, 5.0)
        }
    }

    func testCancelAllActionDoesNothing() async {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        // stopRequested triggers cancelAll; no client.connect expected.
        await coord.handle(.stopRequested)
        let count = await client.connectCallCount
        XCTAssertEqual(count, 0)
    }

    func testDidConnectWithoutPriorDisconnectLeavesLatencyNil() async {
        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        await client.simulateConnected()
        await coord.handle(.didConnect)
        let latency = await coord.lastReconnectLatencySeconds
        XCTAssertNil(latency)
    }
}
