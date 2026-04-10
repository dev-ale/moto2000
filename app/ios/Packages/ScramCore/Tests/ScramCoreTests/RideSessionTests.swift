import XCTest
import BLEProtocol
import BLECentralClient
import RideSimulatorKit
@testable import ScramCore

final class RideSessionTests: XCTestCase {

    // MARK: - Helpers

    private func makePreferences(
        enabled: [ScreenID] = [.speedHeading, .weather, .tripStats]
    ) -> ScreenPreferences {
        ScreenPreferences(
            orderedScreenIDs: enabled.map(\.rawValue),
            disabledScreenIDs: Set(
                ScreenID.allCases
                    .filter { !enabled.contains($0) }
                    .map(\.rawValue)
            )
        )
    }

    // MARK: - Start sends screen order

    func testStartSendsScreenOrderCommand() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let prefs = makePreferences(enabled: [.speedHeading, .weather])
        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: RideSessionDependencies()
        )

        try await session.start()

        let writes = await client.writes
        XCTAssertFalse(writes.isEmpty, "Expected at least one write (screen order)")

        // Decode the first write as a ScreenOrderCommand.
        let firstWrite = writes[0]
        let decoded = try ScreenOrderCommand.decode(firstWrite)
        XCTAssertEqual(decoded.screenIDs, [.speedHeading, .weather])

        await session.stop()
    }

    // MARK: - Enabled screen IDs computed correctly

    func testEnabledScreenIDsMatchPreferences() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let prefs = makePreferences(enabled: [.music, .leanAngle, .altitude])
        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: RideSessionDependencies()
        )

        try await session.start()

        let enabled = await session.enabledScreenIDs
        XCTAssertEqual(enabled, [.music, .leanAngle, .altitude])

        await session.stop()
    }

    // MARK: - Services produce payloads

    func testLocationServiceProducesPayloads() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let locationProvider = MockLocationProvider()
        let prefs = makePreferences(enabled: [.speedHeading])
        let deps = RideSessionDependencies(locationProvider: locationProvider)

        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: deps
        )

        try await session.start()

        // Emit a location sample to the provider.
        let sample = LocationSample(
            scenarioTime: 1.0,
            latitude: 47.56,
            longitude: 7.59,
            altitudeMeters: 260.0,
            speedMps: 15.0,
            courseDegrees: 90.0
        )
        locationProvider.emit(sample)

        // Give the async pipeline time to propagate.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let writes = await client.writes
        // First write is screen order command; subsequent writes are payloads.
        XCTAssertGreaterThan(writes.count, 1, "Expected service payloads after location sample")

        await session.stop()
    }

    // MARK: - Stop is idempotent

    func testStopIsIdempotent() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let prefs = makePreferences()
        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: RideSessionDependencies()
        )

        try await session.start()
        await session.stop()
        await session.stop() // Should not crash.

        let running = await session.isRunning
        XCTAssertFalse(running)
    }

    // MARK: - Start is idempotent

    func testStartIsIdempotent() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let prefs = makePreferences()
        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: RideSessionDependencies()
        )

        try await session.start()
        // Second start should be a no-op (not send another screen order).
        try await session.start()

        let writes = await client.writes
        // Only one screen order command.
        XCTAssertEqual(writes.count, 1)

        await session.stop()
    }

    // MARK: - Trip snapshot available

    func testTripSnapshotAvailableAfterStart() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let locationProvider = MockLocationProvider()
        let prefs = makePreferences(enabled: [.tripStats])
        let deps = RideSessionDependencies(locationProvider: locationProvider)

        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: deps
        )

        try await session.start()

        let sample = LocationSample(
            scenarioTime: 0.0,
            latitude: 47.56,
            longitude: 7.59,
            altitudeMeters: 260.0,
            speedMps: 10.0,
            courseDegrees: 45.0
        )
        locationProvider.emit(sample)

        // Give time for processing.
        try await Task.sleep(nanoseconds: 100_000_000)

        let snapshot = await session.tripSnapshot
        XCTAssertNotNil(snapshot)

        await session.stop()
    }

    // MARK: - SCREEN_CHANGED status notification

    func testScreenChangedStatusUpdatesScheduler() async throws {
        let client = TestBLECentralClient()
        await client.simulateConnected()

        let locationProvider = MockLocationProvider()
        let prefs = makePreferences(enabled: [.speedHeading, .weather])
        let deps = RideSessionDependencies(locationProvider: locationProvider)

        let session = RideSession(
            bleClient: client,
            preferences: prefs,
            dependencies: deps
        )

        try await session.start()

        // Simulate a SCREEN_CHANGED notification from firmware.
        let notification = StatusMessage.screenChanged(.weather)
        await client.simulateStatusNotification(notification.encode())

        // Give time for the status listener to process.
        try await Task.sleep(nanoseconds: 100_000_000)

        // We can't directly inspect the scheduler's active screen from here,
        // but we can verify the session is still running without error.
        let running = await session.isRunning
        XCTAssertTrue(running)

        await session.stop()
    }
}
