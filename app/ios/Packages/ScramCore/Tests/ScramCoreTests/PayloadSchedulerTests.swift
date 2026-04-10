import XCTest
import BLEProtocol
@testable import ScramCore

final class PayloadSchedulerTests: XCTestCase {

    // MARK: - Helpers

    /// Collects all Data values sent through the scheduler.
    private actor SendRecorder {
        var sent: [Data] = []
        func record(_ data: Data) {
            sent.append(data)
        }
        func getSent() -> [Data] { sent }
    }

    private func makeScheduler(
        recorder: SendRecorder,
        backgroundInterval: TimeInterval = 5.0
    ) -> PayloadScheduler {
        PayloadScheduler(
            backgroundInterval: backgroundInterval,
            send: { data in
                await recorder.record(data)
            }
        )
    }

    // MARK: - Active screen payloads forwarded immediately

    func testActiveScreenPayloadForwardedImmediately() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.speedHeading)

        let payload = Data([0x01, 0x02, 0x03])
        await scheduler.enqueue(screenID: .speedHeading, payload: payload)

        let sent = await recorder.getSent()
        // First send is from setActiveScreen (no cached payload), so only the enqueue send
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last, payload)
    }

    func testMultipleActivePayloadsAllForwarded() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.weather)

        let p1 = Data([0x01])
        let p2 = Data([0x02])
        let p3 = Data([0x03])

        await scheduler.enqueue(screenID: .weather, payload: p1)
        await scheduler.enqueue(screenID: .weather, payload: p2)
        await scheduler.enqueue(screenID: .weather, payload: p3)

        let sent = await recorder.getSent()
        XCTAssertEqual(sent, [p1, p2, p3])
    }

    // MARK: - Background screen payloads throttled

    func testBackgroundScreenThrottled() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder, backgroundInterval: 5.0)

        await scheduler.setActiveScreen(.speedHeading)

        // Send multiple payloads for a background screen.
        let p1 = Data([0x10])
        let p2 = Data([0x11])
        let p3 = Data([0x12])

        await scheduler.enqueue(screenID: .weather, payload: p1)
        await scheduler.enqueue(screenID: .weather, payload: p2)
        await scheduler.enqueue(screenID: .weather, payload: p3)

        let sent = await recorder.getSent()
        // Only the first should be forwarded; the rest are throttled.
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first, p1)

        // But the cache should have the latest.
        let cached = await scheduler.latestPayload[.weather]
        XCTAssertEqual(cached, p3)
    }

    // MARK: - Alert payloads bypass throttling

    func testAlertPayloadsAlwaysForwarded() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.speedHeading)

        let call1 = Data([0xA0])
        let call2 = Data([0xA1])
        let blitz1 = Data([0xB0])

        await scheduler.enqueue(screenID: .incomingCall, payload: call1)
        await scheduler.enqueue(screenID: .incomingCall, payload: call2)
        await scheduler.enqueue(screenID: .blitzer, payload: blitz1)

        let sent = await recorder.getSent()
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0], call1)
        XCTAssertEqual(sent[1], call2)
        XCTAssertEqual(sent[2], blitz1)
    }

    // MARK: - Screen change triggers immediate forward of cached payload

    func testScreenChangeSendsCachedPayload() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.speedHeading)

        // Enqueue a background payload for weather (will be sent once as first bg send).
        let weatherPayload = Data([0xCC])
        await scheduler.enqueue(screenID: .weather, payload: weatherPayload)

        let sentBefore = await recorder.getSent()
        XCTAssertEqual(sentBefore.count, 1) // The first background send

        // Now switch to weather — should re-send cached payload.
        await scheduler.setActiveScreen(.weather)

        let sentAfter = await recorder.getSent()
        XCTAssertEqual(sentAfter.count, 2)
        XCTAssertEqual(sentAfter.last, weatherPayload)
    }

    func testScreenChangeToSameScreenDoesNotResend() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.speedHeading)

        let payload = Data([0xDD])
        await scheduler.enqueue(screenID: .speedHeading, payload: payload)

        let sentBefore = await recorder.getSent()
        XCTAssertEqual(sentBefore.count, 1)

        // "Switch" to the same screen — no extra send.
        await scheduler.setActiveScreen(.speedHeading)

        let sentAfter = await recorder.getSent()
        XCTAssertEqual(sentAfter.count, 1)
    }

    func testScreenChangeWithNoCachedPayloadDoesNotSend() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        await scheduler.setActiveScreen(.speedHeading)
        // Switch to a screen with no cached data.
        await scheduler.setActiveScreen(.music)

        let sent = await recorder.getSent()
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - Cache

    func testLatestPayloadCacheUpdated() async {
        let recorder = SendRecorder()
        let scheduler = makeScheduler(recorder: recorder)

        let p1 = Data([0x01])
        let p2 = Data([0x02])

        await scheduler.enqueue(screenID: .tripStats, payload: p1)
        await scheduler.enqueue(screenID: .tripStats, payload: p2)

        let cached = await scheduler.latestPayload[.tripStats]
        XCTAssertEqual(cached, p2)
    }
}
