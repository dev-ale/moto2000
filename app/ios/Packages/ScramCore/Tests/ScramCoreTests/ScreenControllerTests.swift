import XCTest
import BLEProtocol
@testable import ScramCore

final class ScreenControllerTests: XCTestCase {
    /// Drain `count` commands from the controller's stream into an array.
    /// Used by every test below to assert which encoded commands were emitted.
    private func drain(_ controller: ScreenController, count: Int) async -> [ControlCommand] {
        var seen: [ControlCommand] = []
        var iterator = controller.commands.makeAsyncIterator()
        for _ in 0..<count {
            if let next = await iterator.next() {
                seen.append(next)
            }
        }
        return seen
    }

    func test_setActiveScreen_emitsCommandAndUpdatesActive() async throws {
        let controller = ScreenController(initialScreen: .clock)
        await controller.setActiveScreen(.compass)
        let commands = await drain(controller, count: 1)
        XCTAssertEqual(commands, [.setActiveScreen(.compass)])
        let active = await controller.activeScreen
        XCTAssertEqual(active, .compass)
    }

    func test_setBrightness_validValueEmitsCommand() async throws {
        let controller = ScreenController()
        try await controller.setBrightness(75)
        let commands = await drain(controller, count: 1)
        XCTAssertEqual(commands, [.setBrightness(75)])
    }

    func test_setBrightness_outOfRangeThrows() async {
        let controller = ScreenController()
        do {
            try await controller.setBrightness(101)
            XCTFail("expected throw")
        } catch ScreenControllerError.brightnessOutOfRange(let v) {
            XCTAssertEqual(v, 101)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_sleepWakeClear_emitCommands() async throws {
        let controller = ScreenController()
        await controller.sleep()
        await controller.wake()
        await controller.clearAlertOverlay()
        let commands = await drain(controller, count: 3)
        XCTAssertEqual(commands, [.sleep, .wake, .clearAlertOverlay])
    }

    func test_emittedCommandsEncodeToFourBytes() async throws {
        let controller = ScreenController()
        await controller.setActiveScreen(.navigation)
        let commands = await drain(controller, count: 1)
        XCTAssertEqual(commands.first?.encode().count, 4)
    }
}
