import XCTest

@testable import RideSimulatorKit

final class SimulatedClockTests: XCTestCase {
    func test_virtualClock_advancesDeterministically() async {
        let clock = VirtualClock()
        let initial = await clock.nowSeconds
        XCTAssertEqual(initial, 0)
        await clock.advance(to: 5)
        let later = await clock.nowSeconds
        XCTAssertEqual(later, 5)
    }

    func test_virtualClock_sleepResumesWhenClockAdvances() async {
        let clock = VirtualClock()
        let wakeTime: Double = 3.0

        async let sleeper: Void = {
            try? await clock.sleep(until: wakeTime)
        }()

        // Give the sleeper a chance to register its waiter.
        await Task.yield()
        await clock.advance(to: 2.5)  // not yet
        await Task.yield()
        await clock.advance(to: wakeTime)
        _ = await sleeper

        let now = await clock.nowSeconds
        XCTAssertEqual(now, wakeTime)
    }

    func test_virtualClock_sleepReturnsImmediatelyIfAlreadyPastTarget() async throws {
        let clock = VirtualClock(startingAt: 10)
        try await clock.sleep(until: 5)  // should not hang
        let now = await clock.nowSeconds
        XCTAssertEqual(now, 10)
    }

    func test_virtualClock_incrementalAdvanceWakesSleepersAtTheirTarget() async {
        // Drive the clock forward in discrete steps and check that each
        // sleeper resumes when its target is crossed. We avoid relying on
        // cross-task start order by awaiting tasks individually.
        let clock = VirtualClock()
        let observed = WakeRecorder()

        let aTask = Task {
            try? await clock.sleep(until: 3)
            await observed.record("a")
        }
        let bTask = Task {
            try? await clock.sleep(until: 1)
            await observed.record("b")
        }
        let cTask = Task {
            try? await clock.sleep(until: 2)
            await observed.record("c")
        }

        await Task.yield()
        await Task.yield()
        await clock.advance(to: 1)
        _ = await bTask.value
        let afterB = await observed.snapshot
        XCTAssertEqual(afterB, ["b"])

        await clock.advance(to: 2)
        _ = await cTask.value
        let afterC = await observed.snapshot
        XCTAssertEqual(afterC, ["b", "c"])

        await clock.advance(to: 3)
        _ = await aTask.value
        let afterA = await observed.snapshot
        XCTAssertEqual(afterA, ["b", "c", "a"])
    }

    func test_wallClock_rejectsNonPositiveSpeed() {
        XCTAssertThrowsError(try WallClock(speedMultiplier: 0))
        XCTAssertThrowsError(try WallClock(speedMultiplier: -1))
    }

    actor WakeRecorder {
        private(set) var snapshot: [String] = []
        func record(_ tag: String) { snapshot.append(tag) }
    }
}
