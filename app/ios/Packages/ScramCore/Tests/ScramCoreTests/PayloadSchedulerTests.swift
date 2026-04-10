import XCTest
import BLEProtocol
@testable import ScramCore

final class PayloadSchedulerTests: XCTestCase {

    // MARK: - Helpers

    /// Build a raw encoded payload header + zeroed body for testing.
    /// Uses manual byte construction to avoid depending on internal ByteWriter.
    private func makePayload(
        screen: ScreenID,
        alert: Bool = false
    ) -> Data {
        let bodySize = screen.expectedBodySize ?? 0
        var flags: UInt8 = 0
        if alert { flags |= ScreenFlags.alert.rawValue }

        var data = Data(capacity: BLEProtocolConstants.headerSize + bodySize)
        data.append(BLEProtocolConstants.protocolVersion) // byte 0: version
        data.append(screen.rawValue)                       // byte 1: screen_id
        data.append(flags)                                 // byte 2: flags
        data.append(0)                                     // byte 3: reserved
        // bytes 4-5: data_length (little-endian UInt16)
        data.append(UInt8(bodySize & 0xFF))
        data.append(UInt8((bodySize >> 8) & 0xFF))
        // bytes 6-7: trailing reserved
        data.append(0)
        data.append(0)
        // body: zeroed
        data.append(Data(repeating: 0, count: bodySize))
        return data
    }

    // MARK: - Incoming call always sent as alert

    func test_incomingCall_alwaysSentAsAlert_regardlessOfActiveScreen() {
        let scheduler = PayloadScheduler()

        // Set active screen to clock (non-navigation).
        let clockPayload = makePayload(screen: .clock)
        _ = scheduler.schedule(clockPayload)

        let callPayload = makePayload(screen: .incomingCall, alert: true)
        let result = scheduler.schedule(callPayload)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, callPayload)
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)
    }

    func test_incomingCall_alwaysSentDuringNavigation() {
        let scheduler = PayloadScheduler()

        let navPayload = makePayload(screen: .navigation)
        _ = scheduler.schedule(navPayload)

        let callPayload = makePayload(screen: .incomingCall, alert: true)
        let result = scheduler.schedule(callPayload)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, callPayload)
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)
    }

    // MARK: - Blitzer on non-navigation screen sent as alert

    func test_blitzer_nonNavigation_sentAsAlert() {
        let scheduler = PayloadScheduler()

        let clockPayload = makePayload(screen: .clock)
        _ = scheduler.schedule(clockPayload)

        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        let result = scheduler.schedule(blitzerPayload)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, blitzerPayload)
        XCTAssertEqual(scheduler.activeAlert, .blitzer)
    }

    // MARK: - Blitzer during navigation: ALERT flag set on nav payload

    func test_blitzer_duringNavigation_setsAlertFlagOnNavPayload() {
        let scheduler = PayloadScheduler()

        let navPayload = makePayload(screen: .navigation)
        _ = scheduler.schedule(navPayload)

        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        let result = scheduler.schedule(blitzerPayload)

        // Should NOT forward the blitzer payload itself.
        XCTAssertEqual(result.count, 1)
        let forwarded = result[0]

        // Forwarded payload should be the navigation payload with ALERT set.
        XCTAssertEqual(
            PayloadScheduler.peekScreenID(forwarded),
            .navigation,
            "Expected navigation payload, not blitzer overlay"
        )
        XCTAssertTrue(
            PayloadScheduler.peekAlertFlag(forwarded),
            "ALERT bit must be set on the re-sent navigation payload"
        )

        // The original nav payload should NOT have had ALERT set.
        XCTAssertFalse(PayloadScheduler.peekAlertFlag(navPayload))

        XCTAssertEqual(scheduler.activeAlert, .blitzer)
    }

    // MARK: - Incoming call replaces active blitzer alert

    func test_incomingCall_replacesActiveBlitzer() {
        let scheduler = PayloadScheduler()

        // Blitzer alert is active (non-navigation screen).
        let clockPayload = makePayload(screen: .clock)
        _ = scheduler.schedule(clockPayload)
        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        _ = scheduler.schedule(blitzerPayload)
        XCTAssertEqual(scheduler.activeAlert, .blitzer)

        // Incoming call arrives.
        let callPayload = makePayload(screen: .incomingCall, alert: true)
        let result = scheduler.schedule(callPayload)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, callPayload)
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)
    }

    // MARK: - Blitzer cannot replace active incoming call

    func test_blitzer_cannotReplaceActiveIncomingCall() {
        let scheduler = PayloadScheduler()

        // Incoming call alert is active.
        let callPayload = makePayload(screen: .incomingCall, alert: true)
        _ = scheduler.schedule(callPayload)
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)

        // Blitzer arrives — should be suppressed.
        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        let result = scheduler.schedule(blitzerPayload)

        XCTAssertTrue(result.isEmpty, "Blitzer must be suppressed during active call")
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)
    }

    // MARK: - Alert clears when no more alert payloads

    func test_alertClears_whenCallEnds() {
        let scheduler = PayloadScheduler()

        let callPayload = makePayload(screen: .incomingCall, alert: true)
        _ = scheduler.schedule(callPayload)
        XCTAssertEqual(scheduler.activeAlert, .incomingCall)

        // Call ended — ALERT flag cleared.
        let callEndPayload = makePayload(screen: .incomingCall, alert: false)
        _ = scheduler.schedule(callEndPayload)
        XCTAssertNil(scheduler.activeAlert)
    }

    func test_alertClears_whenBlitzerClears() {
        let scheduler = PayloadScheduler()

        let clockPayload = makePayload(screen: .clock)
        _ = scheduler.schedule(clockPayload)

        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        _ = scheduler.schedule(blitzerPayload)
        XCTAssertEqual(scheduler.activeAlert, .blitzer)

        // Blitzer clear — ALERT flag not set.
        let blitzerClearPayload = makePayload(screen: .blitzer, alert: false)
        _ = scheduler.schedule(blitzerClearPayload)
        XCTAssertNil(scheduler.activeAlert)
    }

    // MARK: - Blitzer clear during navigation re-sends nav without ALERT

    func test_blitzerClear_duringNavigation_reSendsNavWithoutAlert() {
        let scheduler = PayloadScheduler()

        let navPayload = makePayload(screen: .navigation)
        _ = scheduler.schedule(navPayload)

        // Blitzer alert.
        let blitzerPayload = makePayload(screen: .blitzer, alert: true)
        _ = scheduler.schedule(blitzerPayload)
        XCTAssertEqual(scheduler.activeAlert, .blitzer)

        // Blitzer clear.
        let blitzerClearPayload = makePayload(screen: .blitzer, alert: false)
        let result = scheduler.schedule(blitzerClearPayload)

        XCTAssertEqual(result.count, 1)
        let forwarded = result[0]

        XCTAssertEqual(
            PayloadScheduler.peekScreenID(forwarded),
            .navigation,
            "Should re-send navigation payload on blitzer clear"
        )
        XCTAssertFalse(
            PayloadScheduler.peekAlertFlag(forwarded),
            "ALERT bit must be cleared on the re-sent navigation payload"
        )
        XCTAssertNil(scheduler.activeAlert)
    }

    // MARK: - Header helpers

    func test_peekScreenID_returnsCorrectID() {
        let navPayload = makePayload(screen: .navigation)
        XCTAssertEqual(PayloadScheduler.peekScreenID(navPayload), .navigation)

        let callPayload = makePayload(screen: .incomingCall)
        XCTAssertEqual(PayloadScheduler.peekScreenID(callPayload), .incomingCall)
    }

    func test_setAlertFlag_setsOnlyBitZero() {
        let payload = makePayload(screen: .navigation)
        XCTAssertFalse(PayloadScheduler.peekAlertFlag(payload))

        let modified = PayloadScheduler.setAlertFlag(on: payload)
        XCTAssertTrue(PayloadScheduler.peekAlertFlag(modified))

        // Other flags byte bits should be unchanged (all zero here).
        let flagsByte = modified[modified.startIndex + 2]
        XCTAssertEqual(flagsByte, ScreenFlags.alert.rawValue)
    }

    func test_clearAlertFlag_clearsOnlyBitZero() {
        let payload = makePayload(screen: .blitzer, alert: true)
        XCTAssertTrue(PayloadScheduler.peekAlertFlag(payload))

        let modified = PayloadScheduler.clearAlertFlag(on: payload)
        XCTAssertFalse(PayloadScheduler.peekAlertFlag(modified))
    }

    // MARK: - Regular (non-alert) payloads pass through

    func test_regularPayloads_passThrough() {
        let scheduler = PayloadScheduler()

        let clockPayload = makePayload(screen: .clock)
        let result = scheduler.schedule(clockPayload)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, clockPayload)
        XCTAssertEqual(scheduler.activeScreen, .clock)
    }
}
