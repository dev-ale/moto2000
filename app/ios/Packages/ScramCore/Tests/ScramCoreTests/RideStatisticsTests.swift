import XCTest

@testable import ScramCore

final class RideStatisticsTests: XCTestCase {
    // MARK: - Empty trips

    func test_compute_emptyTrips_returnsAllZeros() {
        let stats = RideStatistics.compute(from: [])
        XCTAssertEqual(stats.totalRides, 0)
        XCTAssertEqual(stats.totalDistanceKm, 0)
        XCTAssertEqual(stats.totalDurationHours, 0)
        XCTAssertEqual(stats.thisMonthDistanceKm, 0)
    }

    // MARK: - Multiple trips

    func test_compute_multipleTrips_sumsCorrectly() {
        let trips = [
            makeSummary(distanceKm: 100, duration: 3600),
            makeSummary(distanceKm: 50, duration: 7200),
            makeSummary(distanceKm: 75, duration: 1800),
        ]
        let stats = RideStatistics.compute(from: trips)

        XCTAssertEqual(stats.totalRides, 3)
        XCTAssertEqual(stats.totalDistanceKm, 225, accuracy: 0.001)
        XCTAssertEqual(stats.totalDurationHours, 3.5, accuracy: 0.001)
    }

    // MARK: - This month filter

    func test_compute_thisMonth_onlyCountsCurrentMonth() {
        let now = Date()
        let calendar = Calendar.current

        // A trip this month
        let thisMonthTrip = makeSummary(date: now, distanceKm: 120, duration: 3600)

        // A trip from a different month (3 months ago)
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
        let oldTrip = makeSummary(date: threeMonthsAgo, distanceKm: 200, duration: 7200)

        let stats = RideStatistics.compute(from: [thisMonthTrip, oldTrip], now: now)

        XCTAssertEqual(stats.totalRides, 2)
        XCTAssertEqual(stats.totalDistanceKm, 320, accuracy: 0.001)
        XCTAssertEqual(stats.thisMonthDistanceKm, 120, accuracy: 0.001)
    }

    func test_compute_noTripsThisMonth_returnsZeroForThisMonth() {
        let now = Date()
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        let trip = makeSummary(date: lastMonth, distanceKm: 80, duration: 3600)
        let stats = RideStatistics.compute(from: [trip], now: now)

        XCTAssertEqual(stats.totalRides, 1)
        XCTAssertEqual(stats.totalDistanceKm, 80, accuracy: 0.001)
        XCTAssertEqual(stats.thisMonthDistanceKm, 0)
    }

    // MARK: - Helpers

    private func makeSummary(
        date: Date = Date(),
        distanceKm: Double,
        duration: TimeInterval
    ) -> TripSummary {
        TripSummary(
            date: date,
            duration: duration,
            distanceKm: distanceKm,
            avgSpeedKmh: 50,
            maxSpeedKmh: 120,
            elevationGainM: 300
        )
    }
}
