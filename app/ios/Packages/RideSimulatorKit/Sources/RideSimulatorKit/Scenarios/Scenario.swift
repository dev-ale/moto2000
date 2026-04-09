import Foundation

/// Top-level description of a replayable ride.
///
/// A scenario is a deterministic timeline: every sample carries a
/// `scenarioTime` in seconds since the scenario started, and the player
/// emits them in order relative to its clock. Empty arrays are valid —
/// a scenario can be "weather only" or "calls only".
public struct Scenario: Equatable, Sendable, Codable {
    /// Scenario format version. Bump this when the file format changes.
    public static let currentVersion: Int = 1

    public var version: Int
    public var name: String
    public var summary: String
    /// Total duration in seconds. Used by the UI for the progress bar;
    /// events past this mark are still emitted.
    public var durationSeconds: Double
    public var locationSamples: [LocationSample]
    public var headingSamples: [HeadingSample]
    public var motionSamples: [MotionSample]
    public var weatherSnapshots: [WeatherSnapshot]
    public var nowPlayingSnapshots: [NowPlayingSnapshot]
    public var callEvents: [CallEvent]
    public var calendarEvents: [CalendarEvent]

    public init(
        version: Int = Scenario.currentVersion,
        name: String,
        summary: String,
        durationSeconds: Double,
        locationSamples: [LocationSample] = [],
        headingSamples: [HeadingSample] = [],
        motionSamples: [MotionSample] = [],
        weatherSnapshots: [WeatherSnapshot] = [],
        nowPlayingSnapshots: [NowPlayingSnapshot] = [],
        callEvents: [CallEvent] = [],
        calendarEvents: [CalendarEvent] = []
    ) {
        self.version = version
        self.name = name
        self.summary = summary
        self.durationSeconds = durationSeconds
        self.locationSamples = locationSamples
        self.headingSamples = headingSamples
        self.motionSamples = motionSamples
        self.weatherSnapshots = weatherSnapshots
        self.nowPlayingSnapshots = nowPlayingSnapshots
        self.callEvents = callEvents
        self.calendarEvents = calendarEvents
    }
}

public enum ScenarioError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case fileNotFound(String)
    case decodeFailure(String)
}
