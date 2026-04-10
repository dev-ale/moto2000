import XCTest
import RideSimulatorKit

@testable import ScramCore

final class LeanAngleAutoCalibrationTests: XCTestCase {
    private func sample(
        time: Double = 0,
        gx: Double, gy: Double, gz: Double = 0,
        ux: Double = 0, uy: Double = 0, uz: Double = 0
    ) -> MotionSample {
        MotionSample(
            scenarioTime: time,
            gravityX: gx, gravityY: gy, gravityZ: gz,
            userAccelX: ux, userAccelY: uy, userAccelZ: uz
        )
    }

    // MARK: - Pre-calibration state

    func test_autoCalibrate_confidenceStartsAtZero() {
        let calc = LeanAngleCalculator(autoCalibrate: true)
        XCTAssertEqual(calc.confidencePercent, 0)
        XCTAssertFalse(calc.isCalibrated)
        XCTAssertEqual(calc.calibrationMode, .autoCalibrate)
    }

    func test_autoCalibrate_leanStaysZeroBeforeCalibration() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)
        // Feed motion without any location — should stay at zero lean.
        calc = calc.ingesting(sample(time: 0, gx: -0.5, gy: -0.866))
        XCTAssertEqual(calc.currentLeanDegrees, 0)
        XCTAssertEqual(calc.confidencePercent, 0)
    }

    // MARK: - Straight riding triggers calibration

    func test_straightRidingTriggersCalibration() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)

        // Simulate 6 seconds of straight riding at 30 km/h heading north.
        let speedMps = 30.0 / 3.6 // ~8.33 m/s
        for i in 0..<60 {
            let t = Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 0, time: t)
            // Phone in pocket: gravity might be e.g. (0.1, -0.3, -0.95)
            calc = calc.ingesting(sample(time: t, gx: 0.1, gy: -0.3, gz: -0.95))
        }

        XCTAssertTrue(calc.isCalibrated)
        XCTAssertEqual(calc.confidencePercent, 100)
    }

    func test_leanAngleCalculatedAfterCalibration() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)

        // Calibrate with gravity pointing straight down in device frame
        // (simulating phone flat in pocket, gravity = (0, 0, -1)).
        let speedMps = 30.0 / 3.6
        for i in 0..<60 {
            let t = Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 90, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0, gy: 0, gz: -1))
        }

        XCTAssertTrue(calc.isCalibrated)

        // Now tilt: gravity rotates. If the phone tilts so that gravity
        // shifts, the lean angle should be non-zero.
        // Rotate gravity by 30 degrees: cos(30)=0.866, sin(30)=0.5
        // New gravity: (0.5, 0, -0.866) — tilted 30 degrees.
        let t = 6.1
        calc = calc.ingesting(sample(time: t, gx: 0.5, gy: 0, gz: -0.866))

        // The angle between (0,0,-1) and (0.5, 0, -0.866) is ~30 degrees.
        XCTAssertEqual(abs(calc.currentLeanDegrees), 30.0, accuracy: 1.0)
    }

    // MARK: - Low speed does not trigger calibration

    func test_lowSpeedDoesNotTriggerCalibration() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)

        // Speed = 10 km/h (below 20 km/h threshold), straight heading.
        let speedMps = 10.0 / 3.6
        for i in 0..<60 {
            let t = Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 0, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0, gy: -1))
        }

        XCTAssertFalse(calc.isCalibrated)
        XCTAssertEqual(calc.confidencePercent, 0)
    }

    // MARK: - Variable heading does not trigger calibration

    func test_variableHeadingDoesNotTriggerCalibration() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)

        // Good speed but heading swings wildly (0, 90, 180, 270, ...).
        let speedMps = 30.0 / 3.6
        for i in 0..<60 {
            let t = Double(i) * 0.1
            let heading = Double(i % 4) * 90.0
            calc = calc.updatingLocation(speed: speedMps, heading: heading, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0, gy: -1))
        }

        XCTAssertFalse(calc.isCalibrated)
        XCTAssertEqual(calc.confidencePercent, 0)
    }

    // MARK: - Recalibration timer

    func test_recalibrationAfterTenMinutes() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)

        let speedMps = 30.0 / 3.6

        // Initial calibration at t=0..6s with gravity (0, -1, 0).
        for i in 0..<60 {
            let t = Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 0, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0, gy: -1))
        }
        XCTAssertTrue(calc.isCalibrated)
        let firstRef = calc.referenceGravity

        // Jump to t=610s (past the 600s recalibration interval).
        // Feed new straight riding with a different gravity orientation.
        for i in 0..<60 {
            let t = 610.0 + Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 45, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0.1, gy: -0.9, gz: -0.3))
        }

        XCTAssertTrue(calc.isCalibrated)
        XCTAssertEqual(calc.confidencePercent, 100)

        // The reference should have changed because recalibration occurred.
        let secondRef = calc.referenceGravity
        XCTAssertNotNil(secondRef)
        // The gravity reference should differ from the first one.
        let refChanged = firstRef!.x != secondRef!.x
            || firstRef!.y != secondRef!.y
            || firstRef!.z != secondRef!.z
        XCTAssertTrue(refChanged, "Reference gravity should update after recalibration")
    }

    func test_duringRecalibration_keepOldReference() {
        var calc = LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: 1.0)
        let speedMps = 30.0 / 3.6

        // Initial calibration.
        for i in 0..<60 {
            let t = Double(i) * 0.1
            calc = calc.updatingLocation(speed: speedMps, heading: 0, time: t)
            calc = calc.ingesting(sample(time: t, gx: 0, gy: -1))
        }
        XCTAssertTrue(calc.isCalibrated)

        // Jump past recalibration interval but don't provide straight riding.
        // Confidence should NOT drop to 0 — we keep the old reference.
        let t = 610.0
        calc = calc.updatingLocation(speed: speedMps, heading: 0, time: t)
        calc = calc.ingesting(sample(time: t, gx: 0, gy: -1))
        XCTAssertTrue(calc.isCalibrated)
        XCTAssertEqual(calc.confidencePercent, 100)
    }

    // MARK: - Background mode

    func test_backgroundModeSkipsSamples() {
        var calc = LeanAngleCalculator(autoCalibrate: false, smoothingAlpha: 1.0)
        calc = calc.settingBackgroundMode(true)
        XCTAssertTrue(calc.backgroundMode)

        // Feed 20 samples. At decimation factor 10, only 2 should be
        // fully processed (counter hits 1 at sample indices 0 and 10).
        var processedLeans: [Double] = []
        for i in 0..<20 {
            let prev = calc.currentLeanDegrees
            calc = calc.ingesting(sample(
                time: Double(i) * 0.02,
                gx: -0.5, gy: -0.866
            ))
            if calc.currentLeanDegrees != prev || i == 0 {
                processedLeans.append(calc.currentLeanDegrees)
            }
        }

        // samplesSeen should be 20 (all counted) but the lean should have
        // only been updated on the processed samples.
        XCTAssertEqual(calc.samplesSeen, 20)
        // The lean should be ~30 degrees (from the processed samples).
        XCTAssertEqual(calc.currentLeanDegrees, 30.0, accuracy: 1.0)
    }

    func test_backgroundModeCanBeDisabled() {
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0)
        calc = calc.settingBackgroundMode(true)
        XCTAssertTrue(calc.backgroundMode)
        calc = calc.settingBackgroundMode(false)
        XCTAssertFalse(calc.backgroundMode)
    }

    // MARK: - Fixed mode backward compatibility

    func test_fixedMode_confidenceStartsAt100() {
        let calc = LeanAngleCalculator()
        XCTAssertEqual(calc.confidencePercent, 100)
        XCTAssertEqual(calc.calibrationMode, .fixed)
    }

    func test_fixedMode_worksWithoutLocationUpdates() {
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0)
        calc = calc.ingesting(sample(gx: -0.5, gy: -0.866))
        XCTAssertEqual(calc.currentLeanDegrees, 30.0, accuracy: 0.5)
        XCTAssertEqual(calc.confidencePercent, 100)
    }

    func test_reset_preservesCalibrationMode() {
        let calc = LeanAngleCalculator(autoCalibrate: true)
        let reset = calc.reset()
        XCTAssertEqual(reset.calibrationMode, .autoCalibrate)
        XCTAssertEqual(reset.confidencePercent, 0)
    }

    // MARK: - Circular standard deviation

    func test_circularStdDev_constantHeading() {
        let headings = [90.0, 90.0, 90.0, 90.0, 90.0]
        let stdDev = LeanAngleCalculator.circularStdDev(of: headings)
        XCTAssertEqual(stdDev, 0, accuracy: 0.1)
    }

    func test_circularStdDev_slightVariation() {
        let headings = [0.0, 1.0, 2.0, 1.0, 0.0]
        let stdDev = LeanAngleCalculator.circularStdDev(of: headings)
        XCTAssertLessThan(stdDev, 5.0)
    }

    func test_circularStdDev_wrapAround() {
        // Headings near 0/360 boundary — should have small std dev.
        let headings = [359.0, 0.0, 1.0, 360.0, 358.0]
        let stdDev = LeanAngleCalculator.circularStdDev(of: headings)
        XCTAssertLessThan(stdDev, 5.0)
    }

    func test_circularStdDev_wideSpread() {
        let headings = [0.0, 90.0, 180.0, 270.0]
        let stdDev = LeanAngleCalculator.circularStdDev(of: headings)
        XCTAssertGreaterThan(stdDev, 30.0)
    }
}
