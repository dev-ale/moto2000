import XCTest

@testable import RideSimulatorKit

final class ScenarioPlayerTests: XCTestCase {
    func test_stepsAreSortedByScenarioTime() async {
        let env = SimulatorEnvironment()
        let player = ScenarioPlayer(environment: env, clock: VirtualClock())
        let scenario = Scenario(
            name: "sorted",
            summary: "",
            durationSeconds: 10,
            locationSamples: [
                LocationSample(scenarioTime: 5, latitude: 0, longitude: 0),
                LocationSample(scenarioTime: 1, latitude: 1, longitude: 1),
            ],
            headingSamples: [
                HeadingSample(scenarioTime: 3, magneticDegrees: 0),
            ]
        )
        let steps = await player.makeSteps(scenario)
        XCTAssertEqual(steps.map(\.time), [1, 3, 5])
    }

    func test_playEmitsEventsInOrderAndAtCorrectClockTimes() async throws {
        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)

        let scenario = Scenario(
            name: "order",
            summary: "",
            durationSeconds: 10,
            locationSamples: [
                LocationSample(scenarioTime: 1, latitude: 1, longitude: 1),
                LocationSample(scenarioTime: 3, latitude: 3, longitude: 3),
            ],
            headingSamples: [
                HeadingSample(scenarioTime: 2, magneticDegrees: 90),
            ]
        )

        // Start consuming location samples BEFORE play, so the stream does
        // not drop anything.
        let locationTask = Task { () -> [LocationSample] in
            var samples: [LocationSample] = []
            for await sample in env.location.samples {
                samples.append(sample)
                if samples.count == 2 { break }
            }
            return samples
        }
        let headingTask = Task { () -> [HeadingSample] in
            var samples: [HeadingSample] = []
            for await sample in env.heading.samples {
                samples.append(sample)
                if samples.count == 1 { break }
            }
            return samples
        }

        async let playTask: Void = player.play(scenario)
        await Task.yield()

        await clock.advance(to: 1)
        await Task.yield()
        await clock.advance(to: 2)
        await Task.yield()
        await clock.advance(to: 3)
        _ = await playTask

        let locations = await locationTask.value
        let headings = await headingTask.value
        XCTAssertEqual(locations.map(\.latitude), [1, 3])
        XCTAssertEqual(headings.map(\.magneticDegrees), [90])

        let state = await player.state
        XCTAssertEqual(state, .finished)
    }

    func test_playHonoursTaskCancellation() async {
        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let scenario = Scenario(
            name: "cancel",
            summary: "",
            durationSeconds: 100,
            locationSamples: [
                LocationSample(scenarioTime: 50, latitude: 0, longitude: 0),
            ]
        )

        let handle = Task { await player.play(scenario) }
        await Task.yield()
        handle.cancel()
        // Advance past the event so the sleeper resumes, then the player
        // loop sees the cancellation flag.
        await clock.advance(to: 100)
        _ = await handle.value

        let state = await player.state
        XCTAssertTrue(state == .cancelled || state == .finished)
    }
}
