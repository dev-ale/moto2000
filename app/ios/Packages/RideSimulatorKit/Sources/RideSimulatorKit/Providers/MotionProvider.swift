import Foundation

/// Device motion sample used for lean-angle calculation.
///
/// Values are in the iPhone's reference frame. Gravity components sum to
/// ~1G in magnitude when stationary. The lean-angle slice (#12) reduces
/// this into an actual angle.
public struct MotionSample: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    /// Gravity vector X (lateral, positive right).
    public var gravityX: Double
    public var gravityY: Double
    public var gravityZ: Double
    /// User-applied acceleration, separate from gravity.
    public var userAccelX: Double
    public var userAccelY: Double
    public var userAccelZ: Double

    public init(
        scenarioTime: Double,
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double,
        userAccelX: Double = 0,
        userAccelY: Double = 0,
        userAccelZ: Double = 0
    ) {
        self.scenarioTime = scenarioTime
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
        self.userAccelX = userAccelX
        self.userAccelY = userAccelY
        self.userAccelZ = userAccelZ
    }
}

public protocol MotionProvider: Sendable {
    var samples: AsyncStream<MotionSample> { get }
    func start() async
    func stop() async
}
