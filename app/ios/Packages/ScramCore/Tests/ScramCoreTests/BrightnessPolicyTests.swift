import XCTest
@testable import ScramCore

final class BrightnessPolicyTests: XCTestCase {

    // MARK: - Helpers

    /// Create a UTC date.
    private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: 0
        ))!
    }

    /// A standard Basel summer day: sunrise 05:30 UTC, sunset 19:30 UTC
    /// (roughly CEST - 2h from real values, but consistent for testing).
    private var baselSummerSunTimes: SunTimes {
        SunTimes(
            sunrise: utcDate(year: 2025, month: 6, day: 21, hour: 3, minute: 30),
            sunset: utcDate(year: 2025, month: 6, day: 21, hour: 19, minute: 30)
        )
    }

    // MARK: - Time-based (no sensor)

    func testMiddayNoSensor() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: nil
        )
        XCTAssertEqual(decision.brightnessPercent, 100)
        XCTAssertFalse(decision.nightMode)
    }

    func testMidnightNoSensor() {
        let midnight = utcDate(year: 2025, month: 6, day: 21, hour: 0)
        let decision = BrightnessPolicy.decide(
            currentTime: midnight,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: nil
        )
        XCTAssertEqual(decision.brightnessPercent, 30)
        XCTAssertTrue(decision.nightMode)
    }

    func testTwilightBeforeSunset() {
        // 15 minutes before sunset.
        let time = baselSummerSunTimes.sunset.addingTimeInterval(-15 * 60)
        let decision = BrightnessPolicy.decide(
            currentTime: time,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: nil
        )
        // Just before sunset is still daytime (sunset marks the start of dusk).
        // Actually, per policy: < sunsetStart means daytime. sunsetStart == sunset time.
        // 15 min before sunset is still < sunsetStart → daytime.
        XCTAssertEqual(decision.brightnessPercent, 100)
        XCTAssertFalse(decision.nightMode)
    }

    func testTwilightAfterSunset() {
        // 15 minutes after sunset — in dusk twilight window.
        let time = baselSummerSunTimes.sunset.addingTimeInterval(15 * 60)
        let decision = BrightnessPolicy.decide(
            currentTime: time,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: nil
        )
        XCTAssertEqual(decision.brightnessPercent, 50)
        XCTAssertTrue(decision.nightMode)
    }

    // MARK: - Lux-based

    func testLowLux() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: 20,
            userOverride: nil
        )
        XCTAssertTrue(decision.nightMode)
        // 20 lux: fraction = 20/50 = 0.4, brightness = 10 + 0.4*40 = 26.
        XCTAssertEqual(decision.brightnessPercent, 26)
    }

    func testHighLux() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: 500,
            userOverride: nil
        )
        XCTAssertFalse(decision.nightMode)
        XCTAssertEqual(decision.brightnessPercent, 100)
    }

    func testZeroLux() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: 0,
            userOverride: nil
        )
        XCTAssertTrue(decision.nightMode)
        XCTAssertEqual(decision.brightnessPercent, 10)
    }

    // MARK: - User overrides

    func testManualBrightness() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: .manual(percent: 75)
        )
        XCTAssertEqual(decision.brightnessPercent, 75)
        // Daytime → not night mode.
        XCTAssertFalse(decision.nightMode)
    }

    func testForceNightMode() {
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 12)
        let decision = BrightnessPolicy.decide(
            currentTime: noon,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: .autoWithNightMode
        )
        XCTAssertTrue(decision.nightMode)
        XCTAssertEqual(decision.brightnessPercent, 20)
    }

    func testForceDayMode() {
        let midnight = utcDate(year: 2025, month: 6, day: 21, hour: 0)
        let decision = BrightnessPolicy.decide(
            currentTime: midnight,
            sunTimes: baselSummerSunTimes,
            ambientLux: nil,
            userOverride: .autoWithDayMode
        )
        XCTAssertFalse(decision.nightMode)
        XCTAssertEqual(decision.brightnessPercent, 100)
    }
}
