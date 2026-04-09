import Foundation
import XCTest

@testable import RideSimulatorKit

/// Proves the Python scenario generator and the Swift Codable model agree
/// on the scenario JSON format. If this test fails, either the schema
/// drifted or the generator needs updating.
final class FixtureIntegrationTests: XCTestCase {
    private static let relativePath = "../../../../Fixtures/scenarios"

    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.relativePath, isDirectory: true)
            .standardizedFileURL
    }

    func test_baselCityLoopLoads() throws {
        let scenario = try ScenarioLoader.load(
            from: fixturesDirectory.appendingPathComponent("basel-city-loop.json")
        )
        XCTAssertEqual(scenario.name, "basel-city-loop")
        XCTAssertEqual(scenario.version, Scenario.currentVersion)
        XCTAssertFalse(scenario.locationSamples.isEmpty)
        XCTAssertEqual(scenario.callEvents.count, 2)
        XCTAssertEqual(scenario.callEvents.first?.state, .incoming)
        // Location samples should carry monotonically non-decreasing times.
        let times = scenario.locationSamples.map(\.scenarioTime)
        XCTAssertEqual(times, times.sorted())
    }

    func test_highwayStraightLoads() throws {
        let scenario = try ScenarioLoader.load(
            from: fixturesDirectory.appendingPathComponent("highway-straight.json")
        )
        XCTAssertEqual(scenario.name, "highway-straight")
        XCTAssertEqual(scenario.nowPlayingSnapshots.first?.title, "Moving On")
        XCTAssertEqual(scenario.weatherSnapshots.first?.condition, .clear)
    }

    func test_gpxReaderLoadsBaselGpx() throws {
        let samples = try GPXReader.parse(
            contentsOf: fixturesDirectory.appendingPathComponent("basel-city-loop.gpx")
        )
        XCTAssertFalse(samples.isEmpty)
        XCTAssertEqual(samples.first?.scenarioTime, 0)
    }

    @MainActor
    func test_scenarioReplayEmitsEveryLocationSample() async throws {
        let scenario = try ScenarioLoader.load(
            from: fixturesDirectory.appendingPathComponent("basel-city-loop.json")
        )
        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)

        let expectedCount = scenario.locationSamples.count
        let receiver = Task { () -> Int in
            var seen = 0
            for await _ in env.location.samples {
                seen += 1
                if seen == expectedCount { break }
            }
            return seen
        }

        async let playTask: Void = player.play(scenario)
        await Task.yield()
        await clock.advance(to: scenario.durationSeconds + 1)
        _ = await playTask

        let count = await receiver.value
        XCTAssertEqual(count, expectedCount)
    }
}
