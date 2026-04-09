import Foundation

/// One handle that ties every mock provider together so callers can pass a
/// single value around.
///
/// In production code the real implementations will live behind the same
/// protocols; for now there is no "real" variant yet so the dev build uses
/// this directly.
public struct SimulatorEnvironment: Sendable {
    public let location: MockLocationProvider
    public let heading: MockHeadingProvider
    public let motion: MockMotionProvider
    public let weather: MockWeatherProvider
    public let nowPlaying: MockNowPlayingProvider
    public let calls: MockCallObserver
    public let calendar: MockCalendarProvider

    public init(
        location: MockLocationProvider = MockLocationProvider(),
        heading: MockHeadingProvider = MockHeadingProvider(),
        motion: MockMotionProvider = MockMotionProvider(),
        weather: MockWeatherProvider = MockWeatherProvider(),
        nowPlaying: MockNowPlayingProvider = MockNowPlayingProvider(),
        calls: MockCallObserver = MockCallObserver(),
        calendar: MockCalendarProvider = MockCalendarProvider()
    ) {
        self.location = location
        self.heading = heading
        self.motion = motion
        self.weather = weather
        self.nowPlaying = nowPlaying
        self.calls = calls
        self.calendar = calendar
    }
}
