import Foundation
import SQLite3

/// Loads speed cameras from a bundled SQLite database file.
///
/// The database is generated offline by `tools/fetch-speed-cameras/` from
/// OpenStreetMap data and copied into the ScramCore resource bundle. On
/// init the entire table is read into memory (the dataset is small —
/// typically ~1 000 cameras for Switzerland).
public final class BundledSpeedCameraDatabase: SpeedCameraDatabase, @unchecked Sendable {
    private let cameras: [SpeedCamera]

    /// The number of cameras loaded from the database.
    public var count: Int { cameras.count }

    // MARK: - Initialisation

    /// Creates the database by loading cameras from the bundle resource.
    ///
    /// - Parameter bundle: The bundle containing `speed_cameras.sqlite`.
    ///   Defaults to the ScramCore resource bundle.
    public convenience init(bundle: Bundle? = nil) throws {
        let resolvedBundle = bundle ?? .module
        guard let url = resolvedBundle.url(forResource: "speed_cameras", withExtension: "sqlite") else {
            throw BundledDatabaseError.resourceNotFound
        }
        try self.init(url: url)
    }

    /// Creates the database by loading cameras from a SQLite file at *url*.
    public init(url: URL) throws {
        self.cameras = try Self.loadCameras(from: url)
    }

    // MARK: - SpeedCameraDatabase

    public func camerasNear(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) async throws -> [SpeedCamera] {
        cameras.filter { camera in
            GeoMath.haversineMeters(
                lat1: latitude, lon1: longitude,
                lat2: camera.latitude, lon2: camera.longitude
            ) <= radiusMeters
        }
    }

    // MARK: - Private

    private static func loadCameras(from url: URL) throws -> [SpeedCamera] {
        var db: OpaquePointer?
        let path = url.path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw BundledDatabaseError.openFailed(msg)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT lat, lon, speed_limit, type FROM cameras"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw BundledDatabaseError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var cameras: [SpeedCamera] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let lat = sqlite3_column_double(stmt, 0)
            let lon = sqlite3_column_double(stmt, 1)

            let speedLimit: UInt16?
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                speedLimit = UInt16(clamping: sqlite3_column_int(stmt, 2))
            } else {
                speedLimit = nil
            }

            let typeRaw: String
            if let cStr = sqlite3_column_text(stmt, 3) {
                typeRaw = String(cString: cStr)
            } else {
                typeRaw = "unknown"
            }
            let cameraType = SpeedCamera.CameraType(rawValue: typeRaw) ?? .unknown

            cameras.append(SpeedCamera(
                latitude: lat,
                longitude: lon,
                speedLimitKmh: speedLimit,
                cameraType: cameraType
            ))
        }

        return cameras
    }
}

/// Errors from ``BundledSpeedCameraDatabase``.
public enum BundledDatabaseError: Error, Sendable {
    case resourceNotFound
    case openFailed(String)
    case queryFailed(String)
}
