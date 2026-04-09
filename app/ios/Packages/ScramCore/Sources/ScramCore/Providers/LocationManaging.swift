import Foundation

/// Authorization state mirrored from CoreLocation so callers don't have to
/// import CoreLocation directly. The set of cases matches the values we
/// actually care about in the ScramScreen foreground flow.
public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways
}

/// Value type for a single location delivered via ``LocationManagingDelegate``.
///
/// This is the minimal subset of `CLLocation` ``RealLocationProvider``
/// needs to build a ``LocationSample``. Keeping it separate from
/// ``LocationSample`` keeps the boundary pure: the "CoreLocation-like"
/// delegate doesn't know about ride scenarios.
public struct LocationManagingFix: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var altitudeMeters: Double
    public var speedMps: Double
    public var courseDegrees: Double
    public var horizontalAccuracyMeters: Double
    public var timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double,
        speedMps: Double,
        courseDegrees: Double,
        horizontalAccuracyMeters: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.speedMps = speedMps
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.timestamp = timestamp
    }
}

/// Delegate the adapter calls when CoreLocation delivers fixes, errors, or
/// authorization updates. Intentionally narrow — only what
/// ``RealLocationProvider`` needs.
public protocol LocationManagingDelegate: AnyObject, Sendable {
    func locationManager(_ manager: any LocationManaging, didUpdateLocations: [LocationManagingFix])
    func locationManager(_ manager: any LocationManaging, didChangeAuthorization: LocationAuthorization)
    func locationManager(_ manager: any LocationManaging, didFailWithError error: any Error)
}

/// The thin boundary over `CLLocationManager`.
///
/// The production implementation is ``CLLocationManagerAdapter``. Tests
/// inject a fake so they never touch CoreLocation.
public protocol LocationManaging: AnyObject, Sendable {
    var delegate: (any LocationManagingDelegate)? { get set }
    var authorizationStatus: LocationAuthorization { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}
