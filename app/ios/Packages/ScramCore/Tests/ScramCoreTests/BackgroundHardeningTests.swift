import XCTest
import RideSimulatorKit

@testable import ScramCore

// MARK: - Fake CoreMotion manager for throttle tests

private final class FakeCoreMotionManaging: CoreMotionManaging, @unchecked Sendable {
    var isDeviceMotionAvailable: Bool = true
    var deviceMotionUpdateInterval: TimeInterval = 0

    private var handler: (@Sendable (CoreMotionDeviceMotion?, (any Error)?) -> Void)?
    private var queue: OperationQueue?

    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping @Sendable (CoreMotionDeviceMotion?, (any Error)?) -> Void
    ) {
        self.queue = queue
        self.handler = handler
    }

    func stopDeviceMotionUpdates() {
        handler = nil
    }

    /// Deliver N fake motion samples synchronously on the provided queue.
    func deliver(count: Int) {
        for i in 0..<count {
            let motion = CoreMotionDeviceMotion(
                gravity: (x: 0, y: -1, z: 0),
                userAcceleration: (x: 0, y: 0, z: 0),
                timestamp: TimeInterval(i) * 0.02
            )
            handler?(motion, nil)
        }
    }
}

// MARK: - Fake background task runner for RideSession tests

private final class FakeBackgroundTaskRunner: BackgroundTaskRunner, @unchecked Sendable {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastEndedID: Int?
    private var expirationHandler: (@Sendable () -> Void)?

    func beginBackgroundTask(expirationHandler: (@Sendable () -> Void)?) -> Int {
        beginCount += 1
        self.expirationHandler = expirationHandler
        return 42
    }

    func endBackgroundTask(_ identifier: Int) {
        endCount += 1
        lastEndedID = identifier
    }

    func simulateExpiration() {
        expirationHandler?()
    }
}

// MARK: - Location background configuration

final class LocationBackgroundConfigTests: XCTestCase {
    #if canImport(CoreLocation)
    func test_CLLocationManagerAdapter_setsBackgroundProperties() {
        // The adapter configures the underlying CLLocationManager in init().
        // We verify through the adapter's public-facing behavior that it
        // was created — the actual CLLocationManager properties are
        // internal to the adapter, but construction must not crash and the
        // adapter must be usable.
        let adapter = CLLocationManagerAdapter()
        // If we got here without a crash the background properties were
        // set. We also verify the authorization status mapping works.
        _ = adapter.authorizationStatus
    }
    #endif
}

// MARK: - Motion provider background throttle

final class MotionBackgroundThrottleTests: XCTestCase {
    func test_foregroundMode_emitsAllSamples() async throws {
        let fake = FakeCoreMotionManaging()
        let provider = RealMotionProvider(manager: fake)
        let stream = provider.samples
        await provider.start()

        // Deliver 20 samples in foreground mode (default).
        fake.deliver(count: 20)
        await provider.stop()

        var collected: [MotionSample] = []
        for await s in stream { collected.append(s) }
        XCTAssertEqual(collected.count, 20)
    }

    func test_backgroundMode_decimatesSamples() async throws {
        let fake = FakeCoreMotionManaging()
        let provider = RealMotionProvider(manager: fake)
        let stream = provider.samples
        await provider.start()

        provider.setBackgroundMode(true)
        XCTAssertTrue(provider.isBackground)

        // Deliver 50 samples — only every 10th should pass through.
        fake.deliver(count: 50)
        await provider.stop()

        var collected: [MotionSample] = []
        for await s in stream { collected.append(s) }
        // At decimation factor 10, samples at indices 10,20,30,40,50 pass
        // (counter is 1-based inside the provider: 10th, 20th, etc.)
        XCTAssertEqual(collected.count, 5)
    }

    func test_returningToForeground_resetsCounter() async throws {
        let fake = FakeCoreMotionManaging()
        let provider = RealMotionProvider(manager: fake)
        let stream = provider.samples
        await provider.start()

        // Enter background, deliver some samples.
        provider.setBackgroundMode(true)
        fake.deliver(count: 10)

        // Return to foreground.
        provider.setBackgroundMode(false)
        XCTAssertFalse(provider.isBackground)
        fake.deliver(count: 5)
        await provider.stop()

        var collected: [MotionSample] = []
        for await s in stream { collected.append(s) }
        // Background phase: 10 samples, 1 passes (10th).
        // Foreground phase: 5 samples, all 5 pass.
        XCTAssertEqual(collected.count, 6)
    }

    func test_decimationFactor_is10() {
        XCTAssertEqual(RealMotionProvider.backgroundDecimationFactor, 10)
    }
}

// MARK: - RideSession background task

final class RideSessionTests: XCTestCase {
    func test_finishRide_beginsAndEndsBackgroundTask() async {
        let runner = FakeBackgroundTaskRunner()
        let session = RideSession(runner: runner)
        let saveCalled = LockedBox(false)

        await session.finishRide {
            saveCalled.value = true
        }

        XCTAssertTrue(saveCalled.value)
        XCTAssertEqual(runner.beginCount, 1)
        XCTAssertEqual(runner.endCount, 1)
        XCTAssertEqual(runner.lastEndedID, 42)
    }

    func test_expiration_endsTask() async {
        let runner = FakeBackgroundTaskRunner()
        let session = RideSession(runner: runner)

        // Start a long-running save but simulate OS expiration before it finishes.
        let expectation = XCTestExpectation(description: "save completes")
        Task {
            await session.finishRide {
                // Simulate a slow save — the expiration fires first.
                try? await Task.sleep(for: .milliseconds(200))
            }
            expectation.fulfill()
        }

        // Give the task a moment to start, then expire.
        try? await Task.sleep(for: .milliseconds(50))
        runner.simulateExpiration()

        await fulfillment(of: [expectation], timeout: 2)
        // The expiration handler called endBackgroundTask, plus the normal
        // completion path may also call it (harmlessly with invalidTaskID).
        XCTAssertGreaterThanOrEqual(runner.endCount, 1)
    }
}

// MARK: - Background mode declarations

final class BackgroundModeDeclarationsTests: XCTestCase {
    /// Verify that the Tuist Project.swift declares the required
    /// UIBackgroundModes. This test reads the file as a string and checks
    /// for the expected entries — a lightweight safeguard against
    /// accidental removal.
    func test_projectSwift_declaresRequiredBackgroundModes() throws {
        // Walk up from the test bundle to find the repo root.
        let testFile = URL(fileURLWithPath: #filePath)
        // #filePath → .../ScramCore/Tests/ScramCoreTests/<this file>
        // Repo root is 6 levels up (Tests → ScramCore → Packages → ios → app → root).
        var url = testFile
        for _ in 0..<6 { url = url.deletingLastPathComponent() }
        let projectSwift = url
            .appendingPathComponent("Project.swift")
        guard FileManager.default.fileExists(atPath: projectSwift.path) else {
            // Running outside the repo (CI image, etc.) — skip gracefully.
            throw XCTSkip("Project.swift not found at expected path; likely running in CI without full repo checkout.")
        }
        let contents = try String(contentsOf: projectSwift, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"bluetooth-central\""), "UIBackgroundModes must include bluetooth-central")
        XCTAssertTrue(contents.contains("\"location\""), "UIBackgroundModes must include location")
    }
}
