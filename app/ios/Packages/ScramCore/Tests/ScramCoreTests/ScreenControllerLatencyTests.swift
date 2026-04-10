import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScramCore

/// Latency budget for Slice 5 is <500 ms from "user taps a screen row" to
/// "ESP32 finishes drawing the new frame". That budget breaks into roughly
/// three regions:
///
///   - iOS-side: validate, encode, hand off to the BLE write queue.   <  5 ms
///   - BLE round trip on a typical link (write + ack):                ~150 ms
///   - ESP32-side: parse, FSM transition, render the new screen.      ~200 ms
///                                                                    -------
///                                                                    ~355 ms
///
/// This test only owns the iOS-side portion (the only part the
/// ScreenController is responsible for) and asserts it stays under 5 ms.
/// The other two regions live in firmware integration tests and the
/// device-side bring-up report respectively.
final class ScreenControllerLatencyTests: XCTestCase {
    func test_iosSideCommandConstructionIsUnder5ms() async throws {
        let controller = ScreenController()
        let iterations = 200

        // Wire a fake transport that drains commands as fast as the
        // controller can yield them. The VirtualClock isn't strictly
        // needed for the iOS-side measurement (we use ContinuousClock to
        // measure wall time) but we instantiate it here to document that
        // tests are clock-injectable for the day we widen the budget.
        _ = VirtualClock()

        let drain = Task {
            var count = 0
            for await _ in controller.commands {
                count += 1
                if count >= iterations { break }
            }
        }

        let start = ContinuousClock.now
        for i in 0..<iterations {
            // Cycle through commands so the test exercises every code path.
            switch i % 5 {
            case 0: await controller.setActiveScreen(.clock)
            case 1: try await controller.setBrightness(80)
            case 2: await controller.sleep()
            case 3: await controller.wake()
            default: await controller.clearAlertOverlay()
            }
        }
        await drain.value
        let elapsed = ContinuousClock.now - start
        let perCallMs = Double(elapsed.components.attoseconds) / 1e15 / Double(iterations)
            + Double(elapsed.components.seconds) * 1000.0 / Double(iterations)
        XCTAssertLessThan(perCallMs, 5.0,
            "iOS-side command construction averaged \(perCallMs) ms (budget: 5 ms)")
    }
}
