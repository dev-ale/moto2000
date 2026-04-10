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

    /// When in background mode the provider only emits every Nth sample so
    /// the effective rate drops from 50 Hz to ~5 Hz, saving CPU while the
    /// phone is in the rider's pocket.
    public static let backgroundDecimationFactor: Int = 10

    private let manager: any CoreMotionManaging
    private let channel = MotionChannel()
    private let queue: OperationQueue
    private let startTime: Date
    private let updateInterval: TimeInterval
    public let samples: AsyncStream<MotionSample>

    /// Counter used for decimation in background mode. Accessed only from
    /// the motion-update queue so no additional synchronization is needed.
    private var sampleCounter: Int = 0

    /// When `true` only every ``backgroundDecimationFactor``-th sample is
    /// emitted. Accessed from the motion-update queue.
    private var _isBackground: Bool = false
    private let backgroundLock = NSLock()

    /// Whether the provider is currently throttling for background mode.
    public var isBackground: Bool {
        backgroundLock.lock()
        defer { backgroundLock.unlock() }
        return _isBackground
    }

    /// Toggle background throttling. When `background` is `true` only
    /// every ``backgroundDecimationFactor``-th sample is forwarded to the
    /// stream (~5 Hz effective rate at 50 Hz input).
    public func setBackgroundMode(_ background: Bool) {
        backgroundLock.lock()
        _isBackground = background
        if !background { sampleCounter = 0 }
        backgroundLock.unlock()
    }

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
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Background throttle: only forward every Nth sample.
            self.backgroundLock.lock()
            let bg = self._isBackground
            self.sampleCounter += 1
            let counter = self.sampleCounter
            self.backgroundLock.unlock()

            if bg && (counter % RealMotionProvider.backgroundDecimationFactor) != 0 {
                return
            }

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
