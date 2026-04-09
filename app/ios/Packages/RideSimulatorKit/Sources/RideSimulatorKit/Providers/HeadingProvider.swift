import Foundation

public struct HeadingSample: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    /// Magnetic heading in degrees, `0` = north.
    public var magneticDegrees: Double
    /// True heading in degrees. `-1` means "not available".
    public var trueDegrees: Double

    public init(scenarioTime: Double, magneticDegrees: Double, trueDegrees: Double = -1) {
        self.scenarioTime = scenarioTime
        self.magneticDegrees = magneticDegrees
        self.trueDegrees = trueDegrees
    }
}

public protocol HeadingProvider: Sendable {
    var samples: AsyncStream<HeadingSample> { get }
    func start() async
    func stop() async
}
