import XCTest

@testable import ScramCore

final class SpeedCameraUpdaterTests: XCTestCase {

    func test_needsUpdate_trueOnFirstRun() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        // Clear any existing value
        defaults.removeObject(forKey: "scramscreen.blitzer.lastUpdate")

        // Fresh install — no last update timestamp
        let lastUpdate = defaults.double(forKey: "scramscreen.blitzer.lastUpdate")
        XCTAssertEqual(lastUpdate, 0)
        // A new updater should need an update
        let updater = SpeedCameraUpdater()
        XCTAssertTrue(updater.needsUpdate)
    }

    func test_hasLocalDatabase_falseInitially() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID()).sqlite")
        let updater = SpeedCameraUpdater(outputURL: tempURL)
        XCTAssertFalse(updater.hasLocalDatabase)
    }

    func test_databaseURL_inDocuments() {
        let updater = SpeedCameraUpdater()
        XCTAssertTrue(
            updater.databaseURL.path.contains("speed_cameras_updated.sqlite")
        )
    }

    func test_updatableDatabase_fallsToBundled() throws {
        // With no updated file, should fall back to bundled
        let db = try UpdatableSpeedCameraDatabase()
        XCTAssertEqual(db.source, .bundled)
        XCTAssertGreaterThan(db.count, 0)
    }

    func test_updatableDatabase_camerasNearBasel() async throws {
        let db = try UpdatableSpeedCameraDatabase()
        let cameras = try await db.camerasNear(
            latitude: 47.56, longitude: 7.59, radiusMeters: 10_000
        )
        // Basel should have some cameras
        XCTAssertGreaterThan(cameras.count, 0)
    }
}
