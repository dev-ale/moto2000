import XCTest
import RideSimulatorKit

@testable import ScramCore

final class LeanAngleCalculatorTests: XCTestCase {
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

    func test_initialState_isZeroed() {
        let calc = LeanAngleCalculator()
        XCTAssertEqual(calc.currentLeanDegrees, 0)
        XCTAssertEqual(calc.maxLeftLeanDegrees, 0)
        XCTAssertEqual(calc.maxRightLeanDegrees, 0)
        XCTAssertEqual(calc.confidencePercent, 100)
        XCTAssertEqual(calc.samplesSeen, 0)
    }

    func test_uprightSample_givesZeroLean() {
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: 0.0, gy: -1.0))
        XCTAssertEqual(calc.currentLeanDegrees, 0, accuracy: 0.05)
        XCTAssertEqual(calc.samplesSeen, 1)
    }

    func test_thirtyDegreeRightLean_isPositive() {
        // gx = -0.5, gy = -sqrt(3)/2 -> atan2(0.5, 0.866) = +30°
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: -0.5, gy: -0.8660254))
        XCTAssertEqual(calc.currentLeanDegrees, 30.0, accuracy: 0.05)
        XCTAssertEqual(calc.maxRightLeanDegrees, 30.0, accuracy: 0.05)
        XCTAssertEqual(calc.maxLeftLeanDegrees, 0)
    }

    func test_thirtyDegreeLeftLean_isNegative() {
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: 0.5, gy: -0.8660254))
        XCTAssertEqual(calc.currentLeanDegrees, -30.0, accuracy: 0.05)
        XCTAssertEqual(calc.maxLeftLeanDegrees, 30.0, accuracy: 0.05)
        XCTAssertEqual(calc.maxRightLeanDegrees, 0)
    }

    func test_fortyFiveDegreeRightLean() {
        let s = 0.7071067811865476
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: -s, gy: -s))
        XCTAssertEqual(calc.currentLeanDegrees, 45.0, accuracy: 0.05)
    }

    func test_smoothingBlendsTowardPrevious() {
        // First sample: 0°. Second sample raw: 30° right.
        // With alpha=0.2 the smoothed value should be 0*0.8 + 30*0.2 = 6°.
        var calc = LeanAngleCalculator(smoothingAlpha: 0.2)
        calc = calc.ingesting(sample(gx: 0, gy: -1))
        XCTAssertEqual(calc.currentLeanDegrees, 0, accuracy: 0.05)
        calc = calc.ingesting(sample(gx: -0.5, gy: -0.8660254))
        XCTAssertEqual(calc.currentLeanDegrees, 6.0, accuracy: 0.05)
    }

    func test_maxLeftAndMaxRightTrackExtremes() {
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0) // disable smoothing for clarity
        calc = calc.ingesting(sample(gx: -0.5, gy: -0.8660254))    // +30 right
        calc = calc.ingesting(sample(gx: 0.5, gy: -0.8660254))     // -30 left
        calc = calc.ingesting(sample(gx: -0.7071, gy: -0.7071))    // +45 right
        calc = calc.ingesting(sample(gx: 0.342, gy: -0.940))       // -20 left
        XCTAssertEqual(calc.maxRightLeanDegrees, 45.0, accuracy: 0.1)
        XCTAssertEqual(calc.maxLeftLeanDegrees, 30.0, accuracy: 0.1)
        // Current is the *last* sample, not the max.
        XCTAssertEqual(calc.currentLeanDegrees, -20.0, accuracy: 0.1)
    }

    func test_highUserAccelerationDropsConfidence() {
        // 0.25 G of net user accel -> confidence = 100 - 0.25 * 200 = 50
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: 0, gy: -1, ux: 0.25, uy: 0, uz: 0))
        XCTAssertEqual(calc.confidencePercent, 50)
    }

    func test_extremeUserAccelerationClampsConfidenceToZero() {
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: 0, gy: -1, ux: 1.0, uy: 0, uz: 0))
        XCTAssertEqual(calc.confidencePercent, 0)
    }

    func test_lowUserAccelerationKeepsConfidenceHigh() {
        let calc = LeanAngleCalculator()
            .ingesting(sample(gx: 0, gy: -1, ux: 0.02, uy: 0, uz: 0))
        XCTAssertGreaterThanOrEqual(calc.confidencePercent, 95)
    }

    func test_resetReturnsToZero() {
        var calc = LeanAngleCalculator()
        calc = calc.ingesting(sample(gx: -0.5, gy: -0.8660254))
        calc = calc.ingesting(sample(gx: 0.5, gy: -0.8660254))
        let reset = calc.reset()
        XCTAssertEqual(reset.currentLeanDegrees, 0)
        XCTAssertEqual(reset.maxLeftLeanDegrees, 0)
        XCTAssertEqual(reset.maxRightLeanDegrees, 0)
        XCTAssertEqual(reset.samplesSeen, 0)
        XCTAssertEqual(reset.smoothingAlpha, calc.smoothingAlpha)
    }

    func test_snapshotMatchesWireRange() {
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0)
        calc = calc.ingesting(sample(gx: -0.5, gy: -0.8660254))  // +30
        let snap = calc.snapshot
        XCTAssertEqual(snap.currentLeanDegX10, 300)
        XCTAssertEqual(snap.maxRightLeanDegX10, 300)
        XCTAssertEqual(snap.maxLeftLeanDegX10, 0)
        XCTAssertEqual(snap.confidencePercent, 100)
    }

    func test_extremeRightLeanClampsToNinety() {
        // Phone tipped fully right: gx=-1, gy=0 -> atan2(1, 0) = +90°.
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0)
        calc = calc.ingesting(sample(gx: -1.0, gy: 0.0))
        XCTAssertEqual(calc.currentLeanDegrees, 90.0, accuracy: 0.1)
    }

    func test_extremeLeftLeanClampsToNinety() {
        // Phone tipped fully left: gx=+1, gy=0 -> atan2(-1, 0) = -90°.
        var calc = LeanAngleCalculator(smoothingAlpha: 1.0)
        calc = calc.ingesting(sample(gx: 1.0, gy: 0.0))
        XCTAssertEqual(calc.currentLeanDegrees, -90.0, accuracy: 0.1)
    }

    func test_csvFixtureRoundTripsThroughSyntheticTwistyRoad() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "synthetic-twisty-road",
                withExtension: "csv",
                subdirectory: "Fixtures/motion"
            )
        )
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.split(separator: "\n").dropFirst() // header
        var samples: [MotionSample] = []
        for line in lines {
            let cols = line.split(separator: ",").map(String.init)
            guard cols.count >= 7 else { continue }
            samples.append(MotionSample(
                scenarioTime: Double(cols[0]) ?? 0,
                gravityX: Double(cols[1]) ?? 0,
                gravityY: Double(cols[2]) ?? 0,
                gravityZ: Double(cols[3]) ?? 0,
                userAccelX: Double(cols[4]) ?? 0,
                userAccelY: Double(cols[5]) ?? 0,
                userAccelZ: Double(cols[6]) ?? 0
            ))
        }
        XCTAssertGreaterThan(samples.count, 15)

        var calc = LeanAngleCalculator()
        for sample in samples {
            calc = calc.ingesting(sample)
        }
        // The CSV transitions from 0° -> 30° right -> 0° -> 30° left -> 0°.
        // The smoothed final reading should be near zero, max-right should
        // be around 30° (with some EMA lag), and max-left should be around
        // 30° as well.
        XCTAssertEqual(calc.currentLeanDegrees, 0.0, accuracy: 5.0)
        XCTAssertGreaterThan(calc.maxRightLeanDegrees, 15.0)
        XCTAssertLessThanOrEqual(calc.maxRightLeanDegrees, 35.0)
        XCTAssertGreaterThan(calc.maxLeftLeanDegrees, 15.0)
        XCTAssertLessThanOrEqual(calc.maxLeftLeanDegrees, 35.0)
        XCTAssertEqual(calc.confidencePercent, 100)
    }
}
