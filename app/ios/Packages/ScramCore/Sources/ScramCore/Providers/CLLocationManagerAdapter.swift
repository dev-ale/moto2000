#if canImport(CoreLocation)
import CoreLocation
import Foundation

/// Adapts `CLLocationManager` to the ``LocationManaging`` boundary.
///
/// This class is the *only* place in the entire ScramScreen codebase that
/// imports CoreLocation. Everything else routes through the
/// ``LocationManaging`` protocol so tests stay hermetic.
///
/// Thread safety: `CLLocationManager` requires its delegate callbacks on
/// the thread where the manager was initialized. We mirror that contract:
/// callers should construct the adapter on the main actor, and the
/// internal CoreLocation delegate forwards to our
/// ``LocationManagingDelegate`` on the same queue.
public final class CLLocationManagerAdapter: NSObject, LocationManaging, @unchecked Sendable {
    private let manager: CLLocationManager
    public weak var delegate: (any LocationManagingDelegate)?

    public override init() {
        self.manager = CLLocationManager()
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager.activityType = .automotiveNavigation
        // 1 Hz-ish: CoreLocation will call back whenever a new fix is
        // produced; we don't set a distance filter so stationary rides
        // still get updates.
    }

    public var authorizationStatus: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    public func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    public func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    public func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedWhenInUse: return .authorizedWhenInUse
        case .authorizedAlways: return .authorizedAlways
        @unknown default: return .denied
        }
    }
}

extension CLLocationManagerAdapter: CLLocationManagerDelegate {
    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let fixes = locations.map { cl in
            LocationManagingFix(
                latitude: cl.coordinate.latitude,
                longitude: cl.coordinate.longitude,
                altitudeMeters: cl.altitude,
                speedMps: cl.speed,
                courseDegrees: cl.course,
                horizontalAccuracyMeters: cl.horizontalAccuracy,
                timestamp: cl.timestamp
            )
        }
        delegate?.locationManager(self, didUpdateLocations: fixes)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.locationManager(self, didChangeAuthorization: Self.map(manager.authorizationStatus))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }
}
#endif
