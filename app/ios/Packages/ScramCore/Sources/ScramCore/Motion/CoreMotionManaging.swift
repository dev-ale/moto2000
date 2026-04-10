import Foundation

/// CoreMotion-free mirror of `CMDeviceMotion` carrying just the fields the
/// lean-angle pipeline consumes. Lives in ScramCore so production and test
/// code can talk to the same boundary without importing CoreMotion.
public struct CoreMotionDeviceMotion: Sendable {
    public var gravity: (x: Double, y: Double, z: Double)
    public var userAcceleration: (x: Double, y: Double, z: Double)
    public var timestamp: TimeInterval

    public init(
        gravity: (x: Double, y: Double, z: Double),
        userAcceleration: (x: Double, y: Double, z: Double),
        timestamp: TimeInterval
    ) {
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.timestamp = timestamp
    }
}

/// Narrow boundary over `CMMotionManager` that exposes only the surface
/// area `RealMotionProvider` actually needs. Tests inject a fake; the
/// production adapter (`CMMotionManagerAdapter`) lives in its own file
/// gated on `#if canImport(CoreMotion)`.
public protocol CoreMotionManaging: AnyObject, Sendable {
    var isDeviceMotionAvailable: Bool { get }
    var deviceMotionUpdateInterval: TimeInterval { get set }
    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping @Sendable (CoreMotionDeviceMotion?, (any Error)?) -> Void
    )
    func stopDeviceMotionUpdates()
}
