#if canImport(CoreMotion) && !os(macOS)
import CoreMotion
import Foundation

/// Adapts `CMMotionManager` to the ``CoreMotionManaging`` boundary.
///
/// This class is the *only* place in the codebase that imports CoreMotion;
/// everything else routes through ``CoreMotionManaging`` so tests stay
/// hermetic.
public final class CMMotionManagerAdapter: CoreMotionManaging, @unchecked Sendable {
    private let manager: CMMotionManager

    public init(manager: CMMotionManager = CMMotionManager()) {
        self.manager = manager
    }

    public var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    public var deviceMotionUpdateInterval: TimeInterval {
        get { manager.deviceMotionUpdateInterval }
        set { manager.deviceMotionUpdateInterval = newValue }
    }

    public func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping @Sendable (CoreMotionDeviceMotion?, (any Error)?) -> Void
    ) {
        manager.startDeviceMotionUpdates(to: queue) { motion, error in
            guard let motion else {
                handler(nil, error)
                return
            }
            let mirror = CoreMotionDeviceMotion(
                gravity: (
                    x: motion.gravity.x,
                    y: motion.gravity.y,
                    z: motion.gravity.z
                ),
                userAcceleration: (
                    x: motion.userAcceleration.x,
                    y: motion.userAcceleration.y,
                    z: motion.userAcceleration.z
                ),
                timestamp: motion.timestamp
            )
            handler(mirror, nil)
        }
    }

    public func stopDeviceMotionUpdates() {
        manager.stopDeviceMotionUpdates()
    }
}
#endif
