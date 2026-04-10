import Foundation
import RideSimulatorKit

/// Collects GPS coordinates during a ride for later display as a route polyline.
///
/// Only stores points where the rider is actually moving (speed > 1 m/s) and
/// deduplicates points closer than 10 metres apart to keep memory usage low.
public final class RouteCollector: Sendable {
    /// Minimum speed in m/s to record a point (same threshold as TripStatsAccumulator).
    public static let minSpeedMps: Double = 1.0
    /// Minimum distance in metres between stored points.
    public static let minDistanceMeters: Double = 10.0

    private let points: LockedBox<[RoutePoint]> = LockedBox([])
    private let lastPoint: LockedBox<RoutePoint?> = LockedBox(nil)
    private let task: LockedBox<Task<Void, Never>?> = LockedBox(nil)

    public init() {}

    /// Starts collecting coordinates from the given provider's sample stream.
    public func start(provider: some LocationProvider) {
        let collectorTask = Task { [weak self] in
            for await sample in provider.samples {
                guard let self, !Task.isCancelled else { return }
                self.ingest(sample)
            }
        }
        task.update { $0 = collectorTask }
    }

    /// Stops collection and returns all collected route points.
    public func stop() -> [RoutePoint] {
        task.update { t in
            t?.cancel()
            t = nil
        }
        return points.read { $0 }
    }

    // MARK: - Private

    private func ingest(_ sample: LocationSample) {
        guard sample.speedMps > Self.minSpeedMps else { return }

        let newPoint = RoutePoint(latitude: sample.latitude, longitude: sample.longitude)

        let shouldAdd: Bool = lastPoint.read { last in
            guard let last else { return true }
            let distance = GeoMath.haversineMeters(
                lat1: last.latitude, lon1: last.longitude,
                lat2: newPoint.latitude, lon2: newPoint.longitude
            )
            return distance >= Self.minDistanceMeters
        }

        guard shouldAdd else { return }

        points.update { $0.append(newPoint) }
        lastPoint.update { $0 = newPoint }
    }
}

// MARK: - Thread-safe box

/// A simple thread-safe wrapper using NSLock for Sendable conformance.
private final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func read<T>(_ body: (Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&value)
    }
}
