import Foundation

/// Persistent cumulative distance counter backed by UserDefaults.
///
/// Unlike ``TripStatsAccumulator`` which resets per ride, the GPS odometer
/// never resets during normal operation. It tracks total distance driven
/// since first use, similar to a physical odometer.
///
/// The ``addDistance(_:)`` method is called with each GPS sample delta
/// (in meters). The total is persisted immediately so it survives app
/// restarts and crashes.
public final class GPSOdometer: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "scramscreen.gpsOdometer.totalKm"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// Add distance in meters to the cumulative total.
    public func addDistance(_ meters: Double) {
        lock.lock()
        defer { lock.unlock() }
        let current = defaults.double(forKey: key)
        defaults.set(current + meters / 1000.0, forKey: key)
    }

    /// Current cumulative distance in kilometers.
    public var totalKm: Double {
        lock.lock()
        defer { lock.unlock() }
        return defaults.double(forKey: key)
    }

    /// Reset odometer to zero. For testing only — not exposed in UI.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(0.0, forKey: key)
    }
}
