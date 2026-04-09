import Foundation

/// Value type for a single GPS sample emitted by a ``LocationProvider``.
///
/// Mirrors the useful subset of `CLLocation` without importing CoreLocation
/// so the package builds on macOS hosts too.
public struct LocationSample: Equatable, Sendable, Codable {
    /// Seconds since the scenario started.
    public var scenarioTime: Double
    /// WGS-84 latitude in degrees.
    public var latitude: Double
    /// WGS-84 longitude in degrees.
    public var longitude: Double
    /// Altitude in metres above sea level.
    public var altitudeMeters: Double
    /// Ground speed in metres per second. Negative values mean "unknown".
    public var speedMps: Double
    /// Course over ground in degrees, `0` = north. `-1` means "unknown".
    public var courseDegrees: Double
    /// Horizontal accuracy in metres.
    public var horizontalAccuracyMeters: Double

    public init(
        scenarioTime: Double,
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double = 0,
        speedMps: Double = -1,
        courseDegrees: Double = -1,
        horizontalAccuracyMeters: Double = 5
    ) {
        self.scenarioTime = scenarioTime
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.speedMps = speedMps
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}

/// Abstracts iOS CoreLocation so the rest of the app never touches
/// `CLLocationManager` directly.
///
/// The real implementation lands in the Speed + Heading slice (#4). Mock
/// implementations live in ``MockLocationProvider``.
public protocol LocationProvider: Sendable {
    /// Async stream of location samples. Multiple awaiters each get their
    /// own copy.
    var samples: AsyncStream<LocationSample> { get }

    /// Starts delivering samples. Idempotent.
    func start() async

    /// Stops delivering samples. Idempotent.
    func stop() async
}
