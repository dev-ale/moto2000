import BLEProtocol
import Foundation
import RideSimulatorKit
import XCTest
@testable import BLECentralClient

/// Slice 17 success criterion test.
///
/// Replays the `basel-city-loop` scenario through a ``VirtualClock``,
/// scripts a link drop partway through, and asserts that:
/// 1. the reconnect FSM restores the link in well under 5 simulated seconds,
/// 2. the ``LastKnownPayloadCache`` still holds pre-disconnect data, and
/// 3. writes resume successfully once the link comes back.
final class IntegrationReconnectTests: XCTestCase {
    private static let fixturesRelativePath = "../../../../Fixtures/scenarios"

    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.fixturesRelativePath, isDirectory: true)
            .standardizedFileURL
    }

    func testReconnectAcrossBaselCityLoopScenario() async throws {
        let scenario = try ScenarioLoader.load(
            from: fixturesDirectory.appendingPathComponent("basel-city-loop.json")
        )
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        let client = TestBLECentralClient()
        let clock = VirtualClock(startingAt: 0)
        let coord = ReconnectCoordinator(client: client, clock: clock)

        // Bring the link up.
        await coord.handle(.startRequested)
        await client.simulateConnected()
        await coord.handle(.didConnect)

        // Encode each location sample into a tiny synthetic payload; the
        // content doesn't matter — we only need stable bytes to diff.
        func payload(for index: Int) -> Data {
            Data([0xA0, UInt8(index & 0xFF), UInt8((index >> 8) & 0xFF)])
        }

        let samples = scenario.locationSamples
        let dropAfter = samples.count / 3
        XCTAssertGreaterThan(dropAfter, 0, "scenario must have enough samples to mid-drop")

        var preDropWrites: [Data] = []
        var lastPreDropBody: Data = Data()
        var dropTime: Double = 0

        // --- Phase 1: drive writes until the drop point. ---
        for (index, sample) in samples.enumerated() {
            if index == dropAfter {
                dropTime = sample.scenarioTime
                break
            }
            await clock.advance(to: sample.scenarioTime)
            let body = payload(for: index)
            await coord.send(body: body, for: .speedHeading)
            preDropWrites.append(body)
            lastPreDropBody = body
        }

        XCTAssertFalse(preDropWrites.isEmpty)
        let cachedBeforeDrop = await coord.cache.entry(for: .speedHeading)
        XCTAssertEqual(cachedBeforeDrop?.body, lastPreDropBody)

        // --- Phase 2: drop the link. ---
        await clock.advance(to: dropTime)
        await client.simulateDisconnect(reason: .linkLost)
        await coord.handle(.didDisconnect(reason: .linkLost))

        // Attempt a write during the outage — it must silently fail and
        // leave the cache untouched.
        let duringOutageBody = Data([0xFF])
        await coord.send(body: duringOutageBody, for: .speedHeading)
        let cachedDuringOutage = await coord.cache.entry(for: .speedHeading)
        XCTAssertEqual(cachedDuringOutage?.body, lastPreDropBody,
                       "cache should still hold pre-disconnect data during outage")

        // --- Phase 3: advance the virtual clock past the scheduled
        // backoff and fake a successful reconnect. ---
        let backoffSeconds = ReconnectStateMachine.backoffSeconds(forAttempt: 1)
        let reconnectDeadline = dropTime + backoffSeconds + 0.01
        await clock.advance(to: reconnectDeadline)
        // Let any scheduled reconnect tasks run.
        for _ in 0..<8 { await Task.yield() }

        await client.simulateConnected()
        await coord.handle(.didConnect)

        let latency = await coord.lastReconnectLatencySeconds
        XCTAssertNotNil(latency)
        if let latency {
            XCTAssertLessThan(latency, 5.0,
                              "reconnect must complete within 5 simulated seconds")
        }

        // --- Phase 4: resume writes after reconnect. ---
        let postReconnectBody = Data([0xB0, 0xB1, 0xB2])
        let postReconnectTime = reconnectDeadline + 0.05
        await clock.advance(to: postReconnectTime)
        await coord.send(body: postReconnectBody, for: .speedHeading)

        let writesOnClient = await client.writes
        XCTAssertTrue(writesOnClient.contains(postReconnectBody),
                      "client should have received post-reconnect write")

        let cachedAfter = await coord.cache.entry(for: .speedHeading)
        XCTAssertEqual(cachedAfter?.body, postReconnectBody)
        XCTAssertEqual(cachedAfter?.receivedAt, postReconnectTime)

        // Health should be good again.
        let snapshot = await coord.health.snapshot(at: postReconnectTime)
        XCTAssertEqual(snapshot.state, .connected)
        XCTAssertEqual(snapshot.level, .good)
    }
}
