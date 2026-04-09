import Foundation

public struct CalendarEvent: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    public var title: String
    /// Event start in seconds since the scenario started. May be negative
    /// for events that already started.
    public var startsInSeconds: Double
    public var location: String

    public init(
        scenarioTime: Double,
        title: String,
        startsInSeconds: Double,
        location: String
    ) {
        self.scenarioTime = scenarioTime
        self.title = title
        self.startsInSeconds = startsInSeconds
        self.location = location
    }
}

public protocol CalendarProvider: Sendable {
    var events: AsyncStream<CalendarEvent> { get }
    func start() async
    func stop() async
}
