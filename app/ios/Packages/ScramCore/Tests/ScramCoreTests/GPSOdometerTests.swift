import XCTest

@testable import ScramCore

final class GPSOdometerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var odometer: GPSOdometer!

    override func setUp() {
        super.setUp()
        suiteName = "GPSOdometerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        odometer = GPSOdometer(defaults: defaults, key: "test.odometer.totalKm")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_initialValue_isZero() {
        XCTAssertEqual(odometer.totalKm, 0)
    }

    func test_addDistance_accumulatesMeters() {
        odometer.addDistance(1000) // 1 km
        XCTAssertEqual(odometer.totalKm, 1.0, accuracy: 0.001)

        odometer.addDistance(500) // 0.5 km
        XCTAssertEqual(odometer.totalKm, 1.5, accuracy: 0.001)

        odometer.addDistance(2500) // 2.5 km
        XCTAssertEqual(odometer.totalKm, 4.0, accuracy: 0.001)
    }

    func test_persistence_acrossInstances() {
        odometer.addDistance(5000) // 5 km
        XCTAssertEqual(odometer.totalKm, 5.0, accuracy: 0.001)

        // Create a new instance sharing the same defaults and key
        let odometer2 = GPSOdometer(defaults: defaults, key: "test.odometer.totalKm")
        XCTAssertEqual(odometer2.totalKm, 5.0, accuracy: 0.001)

        // Adding to the new instance should accumulate
        odometer2.addDistance(3000) // 3 km
        XCTAssertEqual(odometer2.totalKm, 8.0, accuracy: 0.001)
    }

    func test_reset_setsToZero() {
        odometer.addDistance(10_000) // 10 km
        XCTAssertEqual(odometer.totalKm, 10.0, accuracy: 0.001)

        odometer.reset()
        XCTAssertEqual(odometer.totalKm, 0)
    }

    func test_addDistance_smallIncrements() {
        // Simulate many small GPS deltas
        for _ in 0..<100 {
            odometer.addDistance(10) // 10 meters each
        }
        XCTAssertEqual(odometer.totalKm, 1.0, accuracy: 0.001)
    }
}
