import XCTest
@testable import BLECentralClient

final class ConnectionHealthTests: XCTestCase {
    func testInitialSnapshotIsDown() async {
        let monitor = ConnectionHealthMonitor()
        let snapshot = await monitor.snapshot(at: 0)
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertNil(snapshot.secondsSinceLastWrite)
        XCTAssertEqual(snapshot.level, .down)
    }

    func testConnectedWithRecentWriteIsGood() async {
        let monitor = ConnectionHealthMonitor(degradedAfterSeconds: 2.0)
        await monitor.updateState(.connected)
        await monitor.recordSuccessfulWrite(at: 10.0)
        let snapshot = await monitor.snapshot(at: 11.0)
        XCTAssertEqual(snapshot.level, .good)
        XCTAssertEqual(snapshot.secondsSinceLastWrite, 1.0)
    }

    func testConnectedWithStaleWriteIsDegraded() async {
        let monitor = ConnectionHealthMonitor(degradedAfterSeconds: 2.0)
        await monitor.updateState(.connected)
        await monitor.recordSuccessfulWrite(at: 10.0)
        let snapshot = await monitor.snapshot(at: 15.0)
        XCTAssertEqual(snapshot.level, .degraded)
        XCTAssertEqual(snapshot.secondsSinceLastWrite, 5.0)
    }

    func testConnectedWithoutAnyWriteIsDegraded() async {
        let monitor = ConnectionHealthMonitor()
        await monitor.updateState(.connected)
        let snapshot = await monitor.snapshot(at: 0)
        XCTAssertEqual(snapshot.level, .degraded)
        XCTAssertNil(snapshot.secondsSinceLastWrite)
    }

    func testScanningConnectingReconnectingAreDegraded() async {
        let monitor = ConnectionHealthMonitor()
        await monitor.updateState(.scanning)
        let s1 = await monitor.snapshot(at: 0)
        XCTAssertEqual(s1.level, .degraded)
        await monitor.updateState(.connecting)
        let s2 = await monitor.snapshot(at: 0)
        XCTAssertEqual(s2.level, .degraded)
        await monitor.updateState(.reconnecting(attempt: 3))
        let s3 = await monitor.snapshot(at: 0)
        XCTAssertEqual(s3.level, .degraded)
    }

    func testDisconnectedIsDown() async {
        let monitor = ConnectionHealthMonitor()
        await monitor.updateState(.disconnected(reason: .linkLost))
        let snapshot = await monitor.snapshot(at: 0)
        XCTAssertEqual(snapshot.level, .down)
    }

    func testSecondsSinceLastWriteTracksAcrossTimestamps() async {
        let monitor = ConnectionHealthMonitor()
        await monitor.updateState(.connected)
        await monitor.recordSuccessfulWrite(at: 100.0)
        let s1 = await monitor.snapshot(at: 100.5)
        XCTAssertEqual(s1.secondsSinceLastWrite, 0.5)
        await monitor.recordSuccessfulWrite(at: 110.0)
        let s2 = await monitor.snapshot(at: 110.25)
        XCTAssertEqual(s2.secondsSinceLastWrite, 0.25)
    }

    func testConnectionHealthEquatable() {
        let a = ConnectionHealth(state: .connected, secondsSinceLastWrite: 1.0, level: .good)
        let b = ConnectionHealth(state: .connected, secondsSinceLastWrite: 1.0, level: .good)
        let c = ConnectionHealth(state: .connected, secondsSinceLastWrite: 2.0, level: .good)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
