import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScramCore

/// Scenario-driven integration test: replays the `basel-city-loop.json`
/// scenario through a ``StaticRouteEngine`` + ``ScenarioPlayer`` +
/// ``MockLocationProvider`` + ``NavigationService`` stack and asserts
/// every location sample produces a valid BLE `navigation` payload.
final class NavigationIntegrationTests: XCTestCase {

    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsValidNavPayloads() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        let route = try NavigationRouteTests.loadRouteFixture(named: "basel-city-loop")
        let engine = StaticRouteEngine(fixedRoute: route)

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = NavigationService(
            routeEngine: engine,
            locationProvider: env.location
        )

        let expectedCount = scenario.locationSamples.count
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.navDataPayloads {
                out.append(blob)
                if out.count == expectedCount { return out }
            }
            return out
        }

        // Kick off the NavigationService before the scenario starts
        // emitting samples, so the first sample is captured as origin.
        try await service.start(
            destination: .init(latitude: 47.5482, longitude: 7.5899)
        )

        let playerTask = Task {
            await player.play(scenario)
        }
        await clock.advance(to: scenario.durationSeconds + 1.0)
        await playerTask.value

        // Give the consumer a chance to drain.
        try await Task.sleep(nanoseconds: 100_000_000)
        await env.location.stop()
        await service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(
            received.count,
            expectedCount,
            "one nav payload per location sample"
        )

        // Every payload must decode back to a well-formed nav payload.
        var seenManeuvers = Set<ManeuverType>()
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .navigation(let nav, let flags) = payload else {
                XCTFail("expected navigation payload, got \(payload)")
                return
            }
            XCTAssertEqual(flags, [])
            XCTAssertLessThanOrEqual(nav.streetName.utf8.count, 31)
            seenManeuvers.insert(nav.maneuver)
        }
        // Ensure the tracker actually moved through at least two maneuvers
        // over the 170-second scenario.
        XCTAssertGreaterThanOrEqual(
            seenManeuvers.count,
            2,
            "expected tracker to transition across multiple steps, saw \(seenManeuvers)"
        )
    }
}
