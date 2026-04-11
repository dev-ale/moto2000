import Foundation

/// Speed camera database that uses locally updated data when available,
/// falling back to the bundled database.
///
/// On init, checks for an updated SQLite file in Documents (written by
/// ``SpeedCameraUpdater``). If found and valid, uses it. Otherwise
/// falls back to the bundled database from the app bundle.
public final class UpdatableSpeedCameraDatabase: SpeedCameraDatabase, @unchecked Sendable {
    private let database: any SpeedCameraDatabase

    /// Number of cameras loaded.
    public var count: Int {
        if let bundled = database as? BundledSpeedCameraDatabase {
            return bundled.count
        }
        return 0
    }

    /// Which source is active.
    public let source: Source

    public enum Source: String, Sendable {
        case bundled
        case updated
    }

    public init() throws {
        let updater = SpeedCameraUpdater()
        if updater.hasLocalDatabase {
            do {
                let db = try BundledSpeedCameraDatabase(url: updater.databaseURL)
                self.database = db
                self.source = .updated
                return
            } catch {
                // Fall through to bundled
            }
        }
        self.database = try BundledSpeedCameraDatabase()
        self.source = .bundled
    }

    public func camerasNear(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) async throws -> [SpeedCamera] {
        try await database.camerasNear(
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters
        )
    }
}
