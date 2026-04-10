import Foundation

/// Abstraction over the speed-camera data source.
///
/// Implementations must be Sendable so they can be shared across actors.
/// The query returns cameras within a given radius of a GPS point.
public protocol SpeedCameraDatabase: Sendable {
    func camerasNear(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [SpeedCamera]
}

/// In-memory implementation backed by a flat `[SpeedCamera]` array.
///
/// Queries use haversine distance from `GeoMath`. Suitable for testing
/// and for the MVP where the database is small (hundreds of cameras).
public final class InMemorySpeedCameraDatabase: SpeedCameraDatabase, @unchecked Sendable {
    private let cameras: [SpeedCamera]

    public init(cameras: [SpeedCamera]) {
        self.cameras = cameras
    }

    public func camerasNear(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [SpeedCamera] {
        cameras.filter { camera in
            GeoMath.haversineMeters(
                lat1: latitude, lon1: longitude,
                lat2: camera.latitude, lon2: camera.longitude
            ) <= radiusMeters
        }
    }
}

/// Loads cameras from a JSON file at the given URL.
///
/// The file must contain a JSON array of `SpeedCamera` values. This is the
/// production-ish path: the user (or a future import tool) drops a JSON
/// file of cameras into the app's documents directory. Full OSM XML
/// parsing is a follow-up.
public final class JSONFileSpeedCameraDatabase: SpeedCameraDatabase, @unchecked Sendable {
    private let cameras: [SpeedCamera]

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        self.cameras = try decoder.decode([SpeedCamera].self, from: data)
    }

    public func camerasNear(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [SpeedCamera] {
        cameras.filter { camera in
            GeoMath.haversineMeters(
                lat1: latitude, lon1: longitude,
                lat2: camera.latitude, lon2: camera.longitude
            ) <= radiusMeters
        }
    }
}
