import XCTest
@testable import BLECentralClient

final class ReconnectStateMachineTests: XCTestCase {
    // MARK: - Backoff schedule

    func testBackoffScheduleMatchesSpec() {
        XCTAssertEqual(
            ReconnectStateMachine.backoffSchedule,
            [100, 200, 400, 800, 1600, 3000]
        )
    }

    func testBackoffSecondsClampsToFinalEntry() {
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 1), 0.1, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 2), 0.2, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 3), 0.4, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 4), 0.8, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 5), 1.6, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 6), 3.0, accuracy: 1e-9)
        // Beyond the schedule, the cap holds.
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 7), 3.0, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 42), 3.0, accuracy: 1e-9)
    }

    func testBackoffSecondsClampsAttemptLowerBound() {
        // Zero or negative get clamped to attempt 1.
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(ReconnectStateMachine.backoffSeconds(forAttempt: -3), 0.1, accuracy: 1e-9)
    }

    func testWorstCaseLatencyUnderFiveSeconds() {
        XCTAssertLessThan(ReconnectStateMachine.worstCaseReconnectLatencySeconds, 5.0)
    }

    // MARK: - Initial state

    func testInitialState() async {
        let fsm = ReconnectStateMachine()
        let state = await fsm.state
        XCTAssertEqual(state, .idle)
        let count = await fsm.attemptCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Start / stop

    func testStartRequestedFromIdleStartsScan() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.handle(.startRequested)
        XCTAssertEqual(action, .startScan)
        let state = await fsm.state
        XCTAssertEqual(state, .scanning)
    }

    func testStartRequestedFromDisconnectedStartsScan() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didDisconnect(reason: .userInitiated))
        let action = await fsm.handle(.startRequested)
        XCTAssertEqual(action, .startScan)
    }

    func testStartRequestedIsIdempotentWhileScanning() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.startRequested)
        let action = await fsm.handle(.startRequested)
        XCTAssertEqual(action, .none)
    }

    func testStartRequestedIsIdempotentWhileConnected() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.startRequested)
        _ = await fsm.handle(.didConnect)
        let action = await fsm.handle(.startRequested)
        XCTAssertEqual(action, .none)
    }

    func testStartRequestedIsIdempotentWhileReconnecting() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.startRequested)
        _ = await fsm.handle(.didConnect)
        _ = await fsm.handle(.didDisconnect(reason: .linkLost))
        let action = await fsm.handle(.startRequested)
        XCTAssertEqual(action, .none)
    }

    func testStopRequestedCancelsAll() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.startRequested)
        _ = await fsm.handle(.didConnect)
        let action = await fsm.handle(.stopRequested)
        XCTAssertEqual(action, .cancelAll)
        let state = await fsm.state
        XCTAssertEqual(state, .disconnected(reason: .userInitiated))
        let count = await fsm.attemptCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Disconnect reasons

    func testDisconnectLinkLostSchedulesFirstBackoff() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.startRequested)
        _ = await fsm.handle(.didConnect)
        let action = await fsm.handle(.didDisconnect(reason: .linkLost))
        XCTAssertEqual(action, .scheduleNextAttempt(delaySeconds: 0.1))
        let state = await fsm.state
        XCTAssertEqual(state, .reconnecting(attempt: 1))
        let delays = await fsm.scheduledDelays
        XCTAssertEqual(delays, [0.1])
    }

    func testDisconnectUnknownSchedulesFirstBackoff() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.handle(.didDisconnect(reason: .unknown))
        XCTAssertEqual(action, .scheduleNextAttempt(delaySeconds: 0.1))
        let state = await fsm.state
        XCTAssertEqual(state, .reconnecting(attempt: 1))
    }

    func testDisconnectUserInitiatedIsTerminal() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didConnect)
        let action = await fsm.handle(.didDisconnect(reason: .userInitiated))
        XCTAssertEqual(action, .cancelAll)
        let state = await fsm.state
        XCTAssertEqual(state, .disconnected(reason: .userInitiated))
        XCTAssertTrue(state.isTerminal)
    }

    func testDisconnectUnauthorizedIsTerminal() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.handle(.didDisconnect(reason: .unauthorized))
        XCTAssertEqual(action, .cancelAll)
        let state = await fsm.state
        XCTAssertEqual(state, .disconnected(reason: .unauthorized))
        XCTAssertTrue(state.isTerminal)
    }

    func testDisconnectBluetoothOffIsTerminalFromFSMPerspective() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.handle(.didDisconnect(reason: .bluetoothOff))
        XCTAssertEqual(action, .cancelAll)
        let state = await fsm.state
        XCTAssertEqual(state, .disconnected(reason: .bluetoothOff))
    }

    // MARK: - Reconnect tick / backoff schedule

    func testReconnectTickWhileReconnectingRequestsAttempt() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didDisconnect(reason: .linkLost))
        let action = await fsm.handle(.reconnectTick)
        XCTAssertEqual(action, .attemptConnect)
    }

    func testReconnectTickIgnoredOutsideReconnecting() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.handle(.reconnectTick)
        XCTAssertEqual(action, .none)
    }

    func testAttemptFailedSchedulesEscalatingBackoff() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didDisconnect(reason: .linkLost))
        // attempt 1 scheduled at 100 ms; subsequent failures push to next.
        let expected: [Double] = [0.2, 0.4, 0.8, 1.6, 3.0, 3.0]
        for delay in expected {
            let action = await fsm.attemptFailed()
            XCTAssertEqual(action, .scheduleNextAttempt(delaySeconds: delay))
        }
        let delays = await fsm.scheduledDelays
        XCTAssertEqual(delays, [0.1] + expected)
    }

    func testAttemptFailedIgnoredOutsideReconnecting() async {
        let fsm = ReconnectStateMachine()
        let action = await fsm.attemptFailed()
        XCTAssertEqual(action, .none)
    }

    // MARK: - Recovery resets counters

    func testDidConnectResetsAttemptCount() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didDisconnect(reason: .linkLost))
        _ = await fsm.attemptFailed()
        _ = await fsm.attemptFailed()
        _ = await fsm.handle(.didConnect)
        let state = await fsm.state
        XCTAssertEqual(state, .connected)
        let count = await fsm.attemptCount
        XCTAssertEqual(count, 0)
    }

    func testDuplicateDidConnectIsIdempotent() async {
        let fsm = ReconnectStateMachine()
        _ = await fsm.handle(.didConnect)
        let action = await fsm.handle(.didConnect)
        XCTAssertEqual(action, .none)
        let state = await fsm.state
        XCTAssertEqual(state, .connected)
    }

    // MARK: - ConnectionState helpers

    func testCanWriteOnlyWhenConnected() {
        XCTAssertTrue(ConnectionState.connected.canWrite)
        XCTAssertFalse(ConnectionState.idle.canWrite)
        XCTAssertFalse(ConnectionState.scanning.canWrite)
        XCTAssertFalse(ConnectionState.connecting.canWrite)
        XCTAssertFalse(ConnectionState.reconnecting(attempt: 1).canWrite)
        XCTAssertFalse(ConnectionState.disconnected(reason: .linkLost).canWrite)
    }

    func testIsTerminalMatchesDisconnectReason() {
        XCTAssertFalse(ConnectionState.idle.isTerminal)
        XCTAssertFalse(ConnectionState.connected.isTerminal)
        XCTAssertFalse(ConnectionState.disconnected(reason: .linkLost).isTerminal)
        XCTAssertFalse(ConnectionState.disconnected(reason: .bluetoothOff).isTerminal)
        XCTAssertFalse(ConnectionState.disconnected(reason: .unknown).isTerminal)
        XCTAssertTrue(ConnectionState.disconnected(reason: .userInitiated).isTerminal)
        XCTAssertTrue(ConnectionState.disconnected(reason: .unauthorized).isTerminal)
    }
}
