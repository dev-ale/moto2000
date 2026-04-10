import XCTest

@testable import ScramCore

final class BundledSpeedCameraDatabaseTests: XCTestCase {

    private func fixtureURL() throws -> URL {
        let url = Bundle.module.url(
            forResource: "speed_cameras",
            withExtension: "sqlite",
            subdirectory: "Fixtures"
        )
        return try XCTUnwrap(url, "speed_cameras.sqlite fixture not found in test bundle")
    }

    // MARK: - Loading

    func test_loadsFromSQLiteFile() throws {
        let url = try fixtureURL()
        let db = try BundledSpeedCameraDatabase(url: url)
        // Switzerland has hundreds of speed cameras in OSM.
        XCTAssertGreaterThan(db.count, 100, "Expected at least 100 cameras from the Swiss OSM dataset")
    }

    func test_cameraCountIsReasonable() throws {
        let url = try fixtureURL()
        let db = try BundledSpeedCameraDatabase(url: url)
        // Sanity bounds: Switzerland typically has 500–2000 cameras in OSM.
        XCTAssertGreaterThan(db.count, 500)
        XCTAssertLessThan(db.count, 5000)
    }

    // MARK: - Queries

    func test_camerasNearBern_returnsResults() async throws {
        let url = try fixtureURL()
        let db = try BundledSpeedCameraDatabase(url: url)

        // Bern city centre — there should be at least one camera within 10 km.
        let nearby = try await db.camerasNear(
            latitude: 46.9480,
            longitude: 7.4474,
            radiusMeters: 10_000
        )
        XCTAssertFalse(nearby.isEmpty, "Expected at least one camera near Bern")
    }

    func test_camerasNearNowhere_returnsEmpty() async throws {
        let url = try fixtureURL()
        let db = try BundledSpeedCameraDatabase(url: url)

        // Middle of the Atlantic — no cameras expected.
        let nearby = try await db.camerasNear(
            latitude: 30.0,
            longitude: -40.0,
            radiusMeters: 1_000
        )
        XCTAssertTrue(nearby.isEmpty)
    }

    func test_loadedCamerasHaveValidCoordinates() throws {
        let url = try fixtureURL()
        let db = try BundledSpeedCameraDatabase(url: url)

        // Spot-check: query all cameras via a huge radius centred on Switzerland.
        let task = Task {
            try await db.camerasNear(latitude: 46.8, longitude: 8.2, radiusMeters: 500_000)
        }
        let allCameras = try awaitSync(task)

        for camera in allCameras {
            // All cameras should be within the Swiss bounding box (with margin).
            XCTAssertGreaterThan(camera.latitude, 45.5)
            XCTAssertLessThan(camera.latitude, 48.0)
            XCTAssertGreaterThan(camera.longitude, 5.5)
            XCTAssertLessThan(camera.longitude, 11.0)
        }
    }

    // MARK: - Error handling

    func test_openingNonexistentFile_throws() {
        let bogus = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID()).sqlite")
        XCTAssertThrowsError(try BundledSpeedCameraDatabase(url: bogus))
    }

    // MARK: - Helpers

    /// Block-wait for an async task (test convenience).
    private func awaitSync<T>(_ task: Task<T, Error>) throws -> T {
        let expectation = expectation(description: "async")
        var result: Result<T, Error>!
        Task {
            do {
                let value = try await task.value
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        return try result.get()
    }
}
