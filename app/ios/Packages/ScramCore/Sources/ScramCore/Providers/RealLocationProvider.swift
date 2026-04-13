import Foundation
import RideSimulatorKit

/// Real-device ``LocationProvider`` that forwards CoreLocation fixes (via
/// the injectable ``LocationManaging`` boundary) into an
/// ``AsyncStream`` of ``LocationSample`` values.
///
/// Hermetic tests pass in a `FakeLocationManaging`; production code uses
/// the default ``CLLocationManagerAdapter``.
///
/// Conforms to ``LocationProvider`` from RideSimulatorKit so the rest of
/// the app sees the exact same interface whether it is fed by a scenario
/// or by the real GPS.
public final class RealLocationProvider: LocationProvider, @unchecked Sendable {
    private let manager: any LocationManaging
    private let channel = LocationChannel()
    private let startTime: Date
    public let samples: AsyncStream<LocationSample>

    private let latestLock = NSLock()
    private var _latestSample: LocationSample?

    /// Most recent fix delivered by CoreLocation, or nil if none yet.
    /// Safe to read from any thread. Provided for consumers that need an
    /// occasional snapshot rather than a continuous stream — the
    /// `samples` AsyncStream is single-consumer and shouldn't be split.
    public var latestSample: LocationSample? {
        latestLock.lock()
        defer { latestLock.unlock() }
        return _latestSample
    }

    /// Adapter-delegate shim. Holds a weak back-reference to the provider
    /// so CoreLocation callbacks resolve the provider through this
    /// intermediate. A separate class keeps the adapter's `delegate`
    /// property free of retain cycles.
    private final class Forwarder: LocationManagingDelegate, @unchecked Sendable {
        weak var owner: RealLocationProvider?

        init(owner: RealLocationProvider) {
            self.owner = owner
        }

        func locationManager(
            _ manager: any LocationManaging,
            didUpdateLocations locations: [LocationManagingFix]
        ) {
            owner?.handle(fixes: locations)
        }

        func locationManager(
            _ manager: any LocationManaging,
            didChangeAuthorization: LocationAuthorization
        ) {
            // Authorization handling is the responsibility of the caller
            // that wires the permission UI — the provider itself doesn't
            // make policy decisions here.
        }

        func locationManager(
            _ manager: any LocationManaging,
            didFailWithError error: any Error
        ) {
            // Errors are intentionally swallowed: the stream simply stops
            // producing samples until a new fix arrives. A future slice
            // can surface them via a diagnostics channel.
        }
    }

    private var forwarder: Forwarder?

    public init(manager: any LocationManaging, startTime: Date = Date()) {
        self.manager = manager
        self.startTime = startTime
        self.samples = channel.makeStream()
        let fwd = Forwarder(owner: self)
        self.forwarder = fwd
        manager.delegate = fwd
    }

    #if canImport(CoreLocation)
    /// Convenience initializer that wires up a fresh ``CLLocationManagerAdapter``.
    /// `CLLocationManager` must be created on a thread with a run loop,
    /// hence the `@MainActor` requirement.
    @MainActor
    public convenience init() {
        self.init(manager: CLLocationManagerAdapter())
    }
    #endif

    public func start() async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    public func stop() async {
        manager.stopUpdatingLocation()
        channel.finish()
    }

    // MARK: - Delivery

    fileprivate func handle(fixes: [LocationManagingFix]) {
        for fix in fixes {
            let sample = convert(fix)
            latestLock.lock()
            _latestSample = sample
            latestLock.unlock()
            channel.emit(sample)
        }
    }

    private func convert(_ fix: LocationManagingFix) -> LocationSample {
        let elapsed = fix.timestamp.timeIntervalSince(startTime)
        return LocationSample(
            scenarioTime: elapsed,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitudeMeters: fix.altitudeMeters,
            speedMps: fix.speedMps,
            courseDegrees: fix.courseDegrees,
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters
        )
    }
}
