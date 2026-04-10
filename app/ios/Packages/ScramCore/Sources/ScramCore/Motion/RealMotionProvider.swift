import Foundation
import RideSimulatorKit

/// Real-device ``MotionProvider`` that forwards CoreMotion device-motion
/// updates (via the injectable ``CoreMotionManaging`` boundary) into an
/// ``AsyncStream`` of ``MotionSample`` values.
///
/// Hermetic tests pass in a fake; production code uses the default
/// ``CMMotionManagerAdapter`` on iOS.
public final class RealMotionProvider: MotionProvider, @unchecked Sendable {
    /// Default device-motion update interval (50 Hz). Slice spec calls for
    /// at least 20 Hz; we sample faster so the smoothing filter has more
    /// data to work with.
    public static let defaultUpdateIntervalSeconds: TimeInterval = 1.0 / 50.0

    private let manager: any CoreMotionManaging
    private let channel = MotionChannel()
    private let queue: OperationQueue
    private let startTime: Date
    private let updateInterval: TimeInterval
    public let samples: AsyncStream<MotionSample>

    public init(
        manager: any CoreMotionManaging,
        startTime: Date = Date(),
        updateInterval: TimeInterval = RealMotionProvider.defaultUpdateIntervalSeconds,
        queue: OperationQueue = OperationQueue()
    ) {
        self.manager = manager
        self.startTime = startTime
        self.updateInterval = updateInterval
        self.queue = queue
        self.samples = channel.makeStream()
    }

    #if canImport(CoreMotion) && !os(macOS)
    /// Convenience initializer that wires up a fresh ``CMMotionManagerAdapter``.
    public convenience init() {
        self.init(manager: CMMotionManagerAdapter())
    }
    #endif

    public func start() async {
        guard manager.isDeviceMotionAvailable else {
            // No device motion on this platform — leave the stream empty.
            return
        }
        manager.deviceMotionUpdateInterval = updateInterval
        let channel = self.channel
        let startTime = self.startTime
        manager.startDeviceMotionUpdates(to: queue) { motion, _ in
            guard let motion else { return }
            let sample = MotionSample(
                scenarioTime: Date().timeIntervalSince(startTime),
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z,
                userAccelX: motion.userAcceleration.x,
                userAccelY: motion.userAcceleration.y,
                userAccelZ: motion.userAcceleration.z
            )
            channel.emit(sample)
        }
    }

    public func stop() async {
        manager.stopDeviceMotionUpdates()
        channel.finish()
    }
}
