import Foundation

@testable import ScramCore

/// Hermetic stand-in for ``LocationManaging`` that never touches
/// CoreLocation. Tests poke samples in directly and inspect the
/// `started`/`stopped` counters.
final class FakeLocationManaging: LocationManaging, @unchecked Sendable {
    weak var delegate: (any LocationManagingDelegate)?
    var authorizationStatus: LocationAuthorization = .authorizedWhenInUse
    private(set) var requestWhenInUseCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestWhenInUseAuthorization() {
        requestWhenInUseCount += 1
    }

    func startUpdatingLocation() {
        startCount += 1
    }

    func stopUpdatingLocation() {
        stopCount += 1
    }

    // MARK: - Test helpers

    func deliver(_ fixes: [LocationManagingFix]) {
        delegate?.locationManager(self, didUpdateLocations: fixes)
    }

    func changeAuthorization(to new: LocationAuthorization) {
        authorizationStatus = new
        delegate?.locationManager(self, didChangeAuthorization: new)
    }
}
