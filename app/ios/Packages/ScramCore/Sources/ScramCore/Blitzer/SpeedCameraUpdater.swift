import Foundation
import SQLite3

/// Downloads fresh speed camera data from OpenStreetMap Overpass API
/// and writes it to a SQLite database in the app's Documents directory.
///
/// The updater checks at most once per 30 days (configurable). It runs
/// the same Overpass query as the build-time script in
/// `tools/fetch-speed-cameras/`.
///
/// Coverage: Switzerland + neighboring countries (DE, AT, IT, FR).
public final class SpeedCameraUpdater: Sendable {

    /// Bounding boxes for covered regions.
    /// Switzerland: 45.8-47.9 lat, 5.9-10.5 lon
    /// Extended: includes border areas of DE, AT, IT, FR within ~50km.
    private static let boundingBox = "(45.5,5.5,48.2,10.8)"

    private static let overpassURL = "https://overpass-api.de/api/interpreter"

    private static let overpassQuery = """
    [out:json][timeout:120];
    node["highway"="speed_camera"]\(boundingBox);
    out body;
    """

    private static let updateIntervalSeconds: TimeInterval = 30 * 24 * 3600 // 30 days
    private static let lastUpdateKey = "scramscreen.blitzer.lastUpdate"

    private let documentsURL: URL

    public init() {
        // swiftlint:disable:next force_unwrapping
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        self.documentsURL = docs.appendingPathComponent("speed_cameras_updated.sqlite")
    }

    /// For testing — custom output path.
    public init(outputURL: URL) {
        self.documentsURL = outputURL
    }

    /// URL of the updated database file (may not exist yet).
    public var databaseURL: URL { documentsURL }

    /// Whether an update is available (last update was > 30 days ago).
    public var needsUpdate: Bool {
        let lastUpdate = UserDefaults.standard.double(
            forKey: Self.lastUpdateKey
        )
        guard lastUpdate > 0 else { return true }
        let elapsed = Date().timeIntervalSince1970 - lastUpdate
        return elapsed > Self.updateIntervalSeconds
    }

    /// Whether a local updated database exists.
    public var hasLocalDatabase: Bool {
        FileManager.default.fileExists(atPath: documentsURL.path)
    }

    /// Fetch fresh data from Overpass API and write to local SQLite.
    /// Returns the number of cameras written.
    @discardableResult
    public func update() async throws -> Int {
        let elements = try await fetchOverpass()
        let cameras = elements.compactMap { parseCameraElement($0) }
        guard !cameras.isEmpty else {
            throw SpeedCameraUpdateError.noData
        }
        try writeSQLite(cameras: cameras)
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Self.lastUpdateKey
        )
        return cameras.count
    }

    /// Check if update is needed and run it. Returns camera count or nil
    /// if no update was needed.
    public func updateIfNeeded() async -> Int? {
        guard needsUpdate else { return nil }
        return try? await update()
    }

    // MARK: - Overpass API

    private func fetchOverpass() async throws -> [[String: Any]] {
        var components = URLComponents(string: Self.overpassURL)!  // swiftlint:disable:this force_unwrapping
        components.queryItems = [URLQueryItem(name: "data", value: Self.overpassQuery)]

        var request = URLRequest(url: components.url!)  // swiftlint:disable:this force_unwrapping
        request.httpMethod = "POST"
        request.httpBody = "data=\(Self.overpassQuery)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .data(using: .utf8)
        request.setValue(
            "ScramScreen/1.0 (iOS; speed-camera-updater)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SpeedCameraUpdateError.networkError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            throw SpeedCameraUpdateError.parseError
        }

        return elements
    }

    // MARK: - Parsing

    private static let typeMap: [String: String] = [
        "speed_camera": "fixed",
        "maxspeed": "fixed",
        "average_speed": "section",
        "traffic_signals": "redLight",
        "red_light": "redLight",
        "mobile": "mobile",
    ]

    private func parseCameraElement(_ element: [String: Any]) -> CameraTuple? {
        guard element["type"] as? String == "node",
              let lat = element["lat"] as? Double,
              let lon = element["lon"] as? Double else {
            return nil
        }

        let tags = element["tags"] as? [String: String] ?? [:]
        let speedLimit = tags["maxspeed"].flatMap { Int($0) }
        let enforcement = tags["enforcement"]?.lowercased() ?? ""
        let cameraType = Self.typeMap[enforcement] ?? "unknown"

        return CameraTuple(
            lat: lat, lon: lon,
            speedLimit: speedLimit,
            type: cameraType
        )
    }

    private struct CameraTuple {
        let lat: Double
        let lon: Double
        let speedLimit: Int?
        let type: String
    }

    // MARK: - SQLite

    private func writeSQLite(cameras: [CameraTuple]) throws {
        // Remove old file
        try? FileManager.default.removeItem(at: documentsURL)

        var db: OpaquePointer?
        guard sqlite3_open(documentsURL.path, &db) == SQLITE_OK else {
            throw SpeedCameraUpdateError.databaseError
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, """
        CREATE TABLE cameras (
            id INTEGER PRIMARY KEY,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            speed_limit INTEGER,
            type TEXT NOT NULL DEFAULT 'unknown'
        )
        """, nil, nil, nil)

        let sql = "INSERT INTO cameras (lat, lon, speed_limit, type) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeedCameraUpdateError.databaseError
        }
        defer { sqlite3_finalize(stmt) }

        for camera in cameras {
            sqlite3_bind_double(stmt, 1, camera.lat)
            sqlite3_bind_double(stmt, 2, camera.lon)
            if let limit = camera.speedLimit {
                sqlite3_bind_int(stmt, 3, Int32(limit))
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(
                stmt, 4, camera.type,
                -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    }
}

/// Errors from ``SpeedCameraUpdater``.
public enum SpeedCameraUpdateError: Error, Sendable {
    case networkError
    case parseError
    case noData
    case databaseError
}
