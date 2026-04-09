import Foundation

public enum CallState: String, Equatable, Sendable, Codable {
    case incoming
    case connected
    case ended
}

public struct CallEvent: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    public var state: CallState
    /// Caller identifier as exposed to apps. On iOS the carrier identity is
    /// NOT available to third parties, so scenarios use short placeholders
    /// like "contact-1" or "unknown".
    public var callerHandle: String

    public init(scenarioTime: Double, state: CallState, callerHandle: String) {
        self.scenarioTime = scenarioTime
        self.state = state
        self.callerHandle = callerHandle
    }
}

public protocol CallObserver: Sendable {
    var events: AsyncStream<CallEvent> { get }
    func start() async
    func stop() async
}
