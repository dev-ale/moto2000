import Foundation

/// A single GPS coordinate on a recorded route.
public struct RoutePoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Persists route coordinates as JSON files in the app's Documents directory.
///
/// Each trip's route is stored at `routes/{tripId}.json` as a JSON array of
/// ``RoutePoint`` values. Before saving, the coordinate array is downsampled
/// so files stay small (at most ``maxStoredPoints`` points).
public final class RouteStorage: Sendable {
    /// Maximum number of points persisted per route.
    public static let maxStoredPoints = 500

    private let baseURL: URL

    /// Creates a storage instance rooted at `baseURL`.
    /// Pass a custom URL in tests; production code uses the default.
    public init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL.appendingPathComponent("routes")
        } else {
            // swiftlint:disable:next force_unwrapping
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.baseURL = docs.appendingPathComponent("routes")
        }
    }

    /// Downsamples `coordinates` and writes them to disk for the given trip.
    public func save(tripId: UUID, coordinates: [RoutePoint]) {
        let downsampled = Self.downsample(coordinates)
        guard !downsampled.isEmpty else { return }

        try? FileManager.default.createDirectory(
            at: baseURL, withIntermediateDirectories: true
        )

        let fileURL = url(for: tripId)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(downsampled) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Loads the route for a trip, or returns nil if none exists.
    public func load(tripId: UUID) -> [RoutePoint]? {
        let fileURL = url(for: tripId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([RoutePoint].self, from: data)
    }

    /// Deletes the route file for a trip.
    public func delete(tripId: UUID) {
        let fileURL = url(for: tripId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    private func url(for tripId: UUID) -> URL {
        baseURL.appendingPathComponent("\(tripId.uuidString).json")
    }

    /// Keeps every Nth point so the result has at most ``maxStoredPoints`` entries.
    static func downsample(_ points: [RoutePoint]) -> [RoutePoint] {
        guard points.count > maxStoredPoints else { return points }
        let step = Double(points.count - 1) / Double(maxStoredPoints - 1)
        var result: [RoutePoint] = []
        result.reserveCapacity(maxStoredPoints)
        for i in 0..<maxStoredPoints {
            let index = Int((Double(i) * step).rounded())
            result.append(points[min(index, points.count - 1)])
        }
        return result
    }
}
