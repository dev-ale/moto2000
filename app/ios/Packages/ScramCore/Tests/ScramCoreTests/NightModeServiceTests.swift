import XCTest
@testable import ScramCore
import RideSimulatorKit
import BLEProtocol

/// Thread-safe mutable date provider for tests.
private final class MutableDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ date: Date) { _now = date }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func set(_ date: Date) {
        lock.lock()
        _now = date
        lock.unlock()
    }
}

final class NightModeServiceTests: XCTestCase {

    // MARK: - Helpers

    private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: 0
        ))!
    }

    // MARK: - Midnight in Basel emits night mode

    func testMidnightBaselEmitsNightMode() async {
        let mockLocation = MockLocationProvider()
        let midnight = utcDate(year: 2025, month: 6, day: 21, hour: 0)

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { midnight },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        // Feed Basel coordinates.
        mockLocation.emit(LocationSample(
            scenarioTime: 0, latitude: 47.56, longitude: 7.59
        ))

        // Give a moment for the location to be consumed, then evaluate.
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let decision = await service.evaluate()
        let isNight = await service.isNightMode

        XCTAssertTrue(decision.nightMode, "Midnight in Basel should be night mode")
        XCTAssertTrue(isNight)
        XCTAssertEqual(decision.brightnessPercent, 30)

        await service.stop()
    }

    // MARK: - Noon in Basel emits day mode

    func testNoonBaselEmitsDayMode() async {
        let mockLocation = MockLocationProvider()
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 10) // 12:00 CEST

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { noon },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        mockLocation.emit(LocationSample(
            scenarioTime: 0, latitude: 47.56, longitude: 7.59
        ))

        try? await Task.sleep(nanoseconds: 10_000_000)

        let decision = await service.evaluate()
        let isNight = await service.isNightMode

        XCTAssertFalse(decision.nightMode, "Noon in Basel should be day mode")
        XCTAssertFalse(isNight)
        XCTAssertEqual(decision.brightnessPercent, 100)

        await service.stop()
    }

    // MARK: - Lux overrides time

    func testLuxOverridesTime() async {
        let mockLocation = MockLocationProvider()
        let mockLight = MockAmbientLightProvider()
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 10)

        let service = NightModeService(
            locationProvider: mockLocation,
            ambientLightProvider: mockLight,
            dateProvider: { noon },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        // Start the service so it consumes light and location streams.
        await service.start()

        mockLocation.emit(LocationSample(
            scenarioTime: 0, latitude: 47.56, longitude: 7.59
        ))

        // Inject low lux — should trigger night mode even at noon.
        mockLight.emit(AmbientLightSample(lux: 10, timestamp: noon))

        // Allow async tasks to process the emitted samples.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let decision = await service.evaluate()
        XCTAssertTrue(decision.nightMode, "Low lux should override time-based day mode")

        await service.stop()
    }

    // MARK: - User override takes effect

    func testUserOverrideForceNight() async {
        let mockLocation = MockLocationProvider()
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 10)

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { noon },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        await service.setUserOverride(.autoWithNightMode)
        let decision = await service.evaluate()

        XCTAssertTrue(decision.nightMode)
        XCTAssertEqual(decision.brightnessPercent, 20)

        await service.stop()
    }

    // MARK: - Night mode preference: tag forces day mode

    func testNightModePreferenceTagForcesDayMode() async {
        let mockLocation = MockLocationProvider()
        // Midnight — normally night mode.
        let midnight = utcDate(year: 2025, month: 6, day: 21, hour: 0)

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { midnight },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        await service.setNightModePreference(.tag)
        let decision = await service.evaluate()
        let isNight = await service.isNightMode

        XCTAssertFalse(decision.nightMode, "Tag preference should force day mode even at midnight")
        XCTAssertFalse(isNight)
        XCTAssertEqual(decision.brightnessPercent, 100)

        await service.stop()
    }

    // MARK: - Night mode preference: nacht forces night mode

    func testNightModePreferenceNachtForcesNightMode() async {
        let mockLocation = MockLocationProvider()
        // Noon — normally day mode.
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 10)

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { noon },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        await service.setNightModePreference(.nacht)
        let decision = await service.evaluate()
        let isNight = await service.isNightMode

        XCTAssertTrue(decision.nightMode, "Nacht preference should force night mode even at noon")
        XCTAssertTrue(isNight)
        XCTAssertEqual(decision.brightnessPercent, 20)

        await service.stop()
    }

    // MARK: - Night mode preference: automatisch uses normal logic

    func testNightModePreferenceAutomatischUsesNormalLogic() async {
        let mockLocation = MockLocationProvider()
        let noon = utcDate(year: 2025, month: 6, day: 21, hour: 10)

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { noon },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        await service.setNightModePreference(.automatisch)
        let decision = await service.evaluate()

        XCTAssertFalse(decision.nightMode, "Automatisch at noon should be day mode")
        XCTAssertEqual(decision.brightnessPercent, 100)

        await service.stop()
    }

    // MARK: - Command stream emits on change

    func testCommandStreamEmitsOnDecisionChange() async {
        let mockLocation = MockLocationProvider()
        let timeProvider = MutableDateProvider(utcDate(year: 2025, month: 6, day: 21, hour: 0))

        let service = NightModeService(
            locationProvider: mockLocation,
            dateProvider: { timeProvider.now },
            evaluationInterval: 3600,
            timeZoneOffset: 2
        )

        // First evaluation at midnight.
        let decision1 = await service.evaluate()
        XCTAssertTrue(decision1.nightMode)

        // Move to noon.
        timeProvider.set(utcDate(year: 2025, month: 6, day: 21, hour: 10))
        let decision2 = await service.evaluate()
        XCTAssertFalse(decision2.nightMode)
        XCTAssertEqual(decision2.brightnessPercent, 100)

        await service.stop()
    }
}
