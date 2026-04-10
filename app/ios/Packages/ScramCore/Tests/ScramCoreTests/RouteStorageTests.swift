import XCTest

@testable import ScramCore

final class RouteStorageTests: XCTestCase {
    private var tempDir: URL!
    private var storage: RouteStorage!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RouteStorageTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = RouteStorage(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Save and load round-trip

    func test_saveAndLoad_roundTripsCoordinates() throws {
        let tripId = UUID()
        let points = [
            RoutePoint(latitude: 47.56, longitude: 7.59),
            RoutePoint(latitude: 47.57, longitude: 7.60),
            RoutePoint(latitude: 47.58, longitude: 7.61),
        ]

        storage.save(tripId: tripId, coordinates: points)
        let loaded = storage.load(tripId: tripId)

        let result = try XCTUnwrap(loaded)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].latitude, 47.56, accuracy: 0.0001)
        XCTAssertEqual(result[0].longitude, 7.59, accuracy: 0.0001)
        XCTAssertEqual(result[2].latitude, 47.58, accuracy: 0.0001)
    }

    // MARK: - Load returns nil for unknown trip

    func test_load_returnsNilForUnknownTrip() {
        let result = storage.load(tripId: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Delete removes file

    func test_delete_removesRouteFile() {
        let tripId = UUID()
        let points = [RoutePoint(latitude: 47.56, longitude: 7.59)]
        storage.save(tripId: tripId, coordinates: points)

        XCTAssertNotNil(storage.load(tripId: tripId))

        storage.delete(tripId: tripId)

        XCTAssertNil(storage.load(tripId: tripId))
    }

    // MARK: - Downsampling

    func test_downsample_keepsAtMostMaxPoints() {
        // Create 7200 points (simulating a 2-hour ride at 1Hz)
        var points: [RoutePoint] = []
        for i in 0..<7200 {
            points.append(RoutePoint(
                latitude: 47.56 + Double(i) * 0.0001,
                longitude: 7.59 + Double(i) * 0.0001
            ))
        }

        let tripId = UUID()
        storage.save(tripId: tripId, coordinates: points)

        let loaded = storage.load(tripId: tripId)
        XCTAssertNotNil(loaded)
        XCTAssertLessThanOrEqual(loaded!.count, RouteStorage.maxStoredPoints)
    }

    func test_downsample_preservesSmallArrays() {
        let points = (0..<100).map { i in
            RoutePoint(latitude: 47.56 + Double(i) * 0.001, longitude: 7.59)
        }

        let tripId = UUID()
        storage.save(tripId: tripId, coordinates: points)

        let loaded = storage.load(tripId: tripId)
        XCTAssertEqual(loaded?.count, 100)
    }

    func test_downsample_preservesFirstAndLastPoint() {
        var points: [RoutePoint] = []
        for i in 0..<1000 {
            points.append(RoutePoint(
                latitude: 47.56 + Double(i) * 0.0001,
                longitude: 7.59 + Double(i) * 0.0001
            ))
        }

        let downsampled = RouteStorage.downsample(points)

        XCTAssertEqual(downsampled.first?.latitude, points.first?.latitude)
        XCTAssertEqual(downsampled.last?.latitude, points.last?.latitude)
    }

    func test_save_emptyArray_doesNotCreateFile() {
        let tripId = UUID()
        storage.save(tripId: tripId, coordinates: [])
        XCTAssertNil(storage.load(tripId: tripId))
    }
}
