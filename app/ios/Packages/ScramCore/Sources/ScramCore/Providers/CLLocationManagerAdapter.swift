#if canImport(CoreLocation)
import CoreLocation
import Foundation

/// Adapts `CLLocationManager` to the ``LocationManaging`` boundary.
///
/// This class is the *only* place in the entire ScramScreen codebase that
/// imports CoreLocation. Everything else routes through the
/// ``LocationManaging`` protocol so tests stay hermetic.
///
/// **Threading**: `CLLocationManager` will only deliver delegate
/// callbacks on a thread that has an active run loop. Creating it from
/// a background `Task` (like RideSessionCoordinator does) silently
/// produces no fixes. The adapter therefore hops to the main actor for
/// init and start so CoreLocation always has a real run loop to call
/// back on.
public final class CLLocationManagerAdapter: NSObject, LocationManaging, @unchecked Sendable {
    private let manager: CLLocationManager
    public weak var delegate: (any LocationManagingDelegate)?

    @MainActor
    public override init() {
        self.manager = CLLocationManager()
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.manager.activityType = .automotiveNavigation
        self.manager.distanceFilter = kCLDistanceFilterNone
        #if os(iOS)
        self.manager.allowsBackgroundLocationUpdates = true
        self.manager.pausesLocationUpdatesAutomatically = false
        self.manager.showsBackgroundLocationIndicator = true
        #endif
    }

    public var authorizationStatus: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    public func requestWhenInUseAuthorization() {
        // CLLocationManager is not thread-safe. Dispatch to main so the
        // call lands on the same run loop that created the manager.
        DispatchQueue.main.async { [manager] in
            manager.requestWhenInUseAuthorization()
        }
    }

    public func startUpdatingLocation() {
        DispatchQueue.main.async { [manager] in
            manager.startUpdatingLocation()
        }
    }

    public func stopUpdatingLocation() {
        DispatchQueue.main.async { [manager] in
            manager.stopUpdatingLocation()
        }
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
        // Reject fixes CoreLocation already flagged as bad: a negative
        // horizontalAccuracy means "no fix", and >50 m on a moto is
        // wide enough to produce noise jumps in km/h.
        let good = locations.filter { cl in
            cl.horizontalAccuracy >= 0 && cl.horizontalAccuracy <= 50
        }
        let fixes = good.map { cl in
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
        if !fixes.isEmpty {
            delegate?.locationManager(self, didUpdateLocations: fixes)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        delegate?.locationManager(self, didChangeAuthorization: Self.map(manager.authorizationStatus))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }
}
#endif
