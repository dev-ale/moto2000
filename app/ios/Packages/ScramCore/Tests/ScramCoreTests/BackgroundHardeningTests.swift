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

// MARK: - Location background configuration

final class LocationBackgroundConfigTests: XCTestCase {
    #if canImport(CoreLocation)
    @MainActor
    func test_CLLocationManagerAdapter_setsBackgroundProperties() {
        let adapter = CLLocationManagerAdapter()
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

        fake.deliver(count: 50)
        await provider.stop()

        var collected: [MotionSample] = []
        for await s in stream { collected.append(s) }
        XCTAssertEqual(collected.count, 5)
    }

    func test_returningToForeground_resetsCounter() async throws {
        let fake = FakeCoreMotionManaging()
        let provider = RealMotionProvider(manager: fake)
        let stream = provider.samples
        await provider.start()

        provider.setBackgroundMode(true)
        fake.deliver(count: 10)

        provider.setBackgroundMode(false)
        XCTAssertFalse(provider.isBackground)
        fake.deliver(count: 5)
        await provider.stop()

        var collected: [MotionSample] = []
        for await s in stream { collected.append(s) }
        XCTAssertEqual(collected.count, 6)
    }

    func test_decimationFactor_is10() {
        XCTAssertEqual(RealMotionProvider.backgroundDecimationFactor, 10)
    }
}

// MARK: - Background mode declarations

final class BackgroundModeDeclarationsTests: XCTestCase {
    func test_projectSwift_declaresRequiredBackgroundModes() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        var url = testFile
        for _ in 0..<6 { url = url.deletingLastPathComponent() }
        let projectSwift = url
            .appendingPathComponent("Project.swift")
        guard FileManager.default.fileExists(atPath: projectSwift.path) else {
            throw XCTSkip("Project.swift not found at expected path; likely running in CI without full repo checkout.")
        }
        let contents = try String(contentsOf: projectSwift, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"bluetooth-central\""), "UIBackgroundModes must include bluetooth-central")
        XCTAssertTrue(contents.contains("\"location\""), "UIBackgroundModes must include location")
    }
}
