import XCTest
@testable import ScramCore

final class SunriseSunsetCalculatorTests: XCTestCase {

    // MARK: - Helpers

    /// Make a UTC date from components.
    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        dc.hour = hour
        dc.minute = minute
        dc.second = 0
        return cal.date(from: dc)!
    }

    /// Extract hour and minute in the given UTC offset.
    private func hourMinute(_ date: Date, utcOffset: Int) -> (Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: utcOffset * 3600)!
        let dc = cal.dateComponents([.hour, .minute], from: date)
        return (dc.hour!, dc.minute!)
    }

    /// Assert that a time is within +/- `toleranceMinutes` of an expected
    /// hour:minute in the given UTC offset.
    private func assertTimeApprox(
        _ actual: Date,
        expectedHour: Int,
        expectedMinute: Int,
        utcOffset: Int,
        toleranceMinutes: Int = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (h, m) = hourMinute(actual, utcOffset: utcOffset)
        let actualTotal = h * 60 + m
        let expectedTotal = expectedHour * 60 + expectedMinute
        let diff = abs(actualTotal - expectedTotal)
        XCTAssertLessThanOrEqual(
            diff, toleranceMinutes,
            "Expected ~\(expectedHour):\(String(format: "%02d", expectedMinute)) but got \(h):\(String(format: "%02d", m)) (diff \(diff) min)",
            file: file, line: line
        )
    }

    // MARK: - Basel summer solstice

    func testBaselSummerSolstice() {
        // Basel: 47.56 N, 7.59 E. June 21 — sunrise ~05:30 CEST = ~03:30 UTC,
        // sunset ~21:30 CEST = ~19:30 UTC. Results are UTC Date objects.
        let date = utcDate(year: 2025, month: 6, day: 21)
        let result = SunriseSunsetCalculator.calculate(
            latitude: 47.56, longitude: 7.59, date: date, timeZoneOffset: 2
        )
        assertTimeApprox(result.sunrise, expectedHour: 3, expectedMinute: 30, utcOffset: 0)
        assertTimeApprox(result.sunset, expectedHour: 19, expectedMinute: 30, utcOffset: 0)
    }

    // MARK: - Basel winter solstice

    func testBaselWinterSolstice() {
        // Dec 21 — sunrise ~08:10 CET = ~07:10 UTC, sunset ~16:35 CET = ~15:35 UTC.
        let date = utcDate(year: 2025, month: 12, day: 21)
        let result = SunriseSunsetCalculator.calculate(
            latitude: 47.56, longitude: 7.59, date: date, timeZoneOffset: 1
        )
        assertTimeApprox(result.sunrise, expectedHour: 7, expectedMinute: 10, utcOffset: 0)
        assertTimeApprox(result.sunset, expectedHour: 15, expectedMinute: 35, utcOffset: 0)
    }

    // MARK: - Tromso midnight sun

    func testTromsoMidnightSun() {
        // Tromso 69.65 N, 18.96 E on June 21 — midnight sun.
        // Calculator should return a full-day window.
        let date = utcDate(year: 2025, month: 6, day: 21)
        let result = SunriseSunsetCalculator.calculate(
            latitude: 69.65, longitude: 18.96, date: date, timeZoneOffset: 2
        )
        // Full-day window: sunset - sunrise should be ~24h.
        let duration = result.sunset.timeIntervalSince(result.sunrise)
        XCTAssertGreaterThanOrEqual(duration, 86000, "Expected ~24h window for midnight sun")
    }

    // MARK: - Equator on equinox

    func testEquatorEquinox() {
        // 0 N, 0 E on March 20 — sunrise ~06:00, sunset ~18:00 UTC
        let date = utcDate(year: 2025, month: 3, day: 20)
        let result = SunriseSunsetCalculator.calculate(
            latitude: 0, longitude: 0, date: date, timeZoneOffset: 0
        )
        assertTimeApprox(result.sunrise, expectedHour: 6, expectedMinute: 0, utcOffset: 0)
        assertTimeApprox(result.sunset, expectedHour: 18, expectedMinute: 0, utcOffset: 0)
    }

    // MARK: - Sunrise before sunset invariant

    func testSunriseBeforeSunset() {
        // For a normal latitude (not polar), sunrise should be before sunset.
        let date = utcDate(year: 2025, month: 9, day: 15)
        let result = SunriseSunsetCalculator.calculate(
            latitude: 40.71, longitude: -74.01, date: date, timeZoneOffset: -4
        )
        XCTAssertLessThan(result.sunrise, result.sunset)
    }
}
