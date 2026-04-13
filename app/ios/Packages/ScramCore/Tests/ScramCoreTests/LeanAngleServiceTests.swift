import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class LeanAngleServiceTests: XCTestCase {
    func test_encode_uprightSampleProducesZeroLean() throws {
        let service = LeanAngleService(provider: StubMotionProvider())
        // Calibration captures the current (upright) sample as the zero
        // reference; confidence stays 0 until the rider calibrates.
        _ = service.encode(MotionSample(
            scenarioTime: 0,
            gravityX: 0, gravityY: -1, gravityZ: 0
        ))
        service.calibrate()
        let blob = service.encode(MotionSample(
            scenarioTime: 0,
            gravityX: 0, gravityY: -1, gravityZ: 0
        ))
        let payload = try ScreenPayloadCodec.decode(XCTUnwrap(blob))
        guard case .leanAngle(let data, _) = payload else {
            XCTFail("expected leanAngle payload")
            return
        }
        XCTAssertEqual(data.currentLeanDegX10, 0)
        XCTAssertEqual(data.maxLeftLeanDegX10, 0)
        XCTAssertEqual(data.maxRightLeanDegX10, 0)
        XCTAssertEqual(data.confidencePercent, 100)
    }

    func test_encode_beforeCalibration_reportsZeroConfidence() throws {
        let service = LeanAngleService(provider: StubMotionProvider())
        let blob = service.encode(MotionSample(
            scenarioTime: 0,
            gravityX: 0, gravityY: -1, gravityZ: 0
        ))
        let payload = try ScreenPayloadCodec.decode(XCTUnwrap(blob))
        guard case .leanAngle(let data, _) = payload else {
            XCTFail("expected leanAngle payload")
            return
        }
        XCTAssertEqual(data.confidencePercent, 0)
    }

    func test_encode_thirtyDegreeRightLeanProducesPositiveValue() throws {
        // Use alpha=1 (no smoothing) so the very first sample lands at the
        // raw target.
        let service = LeanAngleService(
            provider: StubMotionProvider(),
            smoothingAlpha: 1.0
        )
        let blob = service.encode(MotionSample(
            scenarioTime: 0,
            gravityX: -0.5, gravityY: -0.8660254, gravityZ: 0
        ))
        let payload = try ScreenPayloadCodec.decode(XCTUnwrap(blob))
        guard case .leanAngle(let data, _) = payload else {
            XCTFail()
            return
        }
        XCTAssertEqual(Int(data.currentLeanDegX10), 300)
        XCTAssertEqual(Int(data.maxRightLeanDegX10), 300)
    }

    func test_encode_tracksMaxAcrossMultipleSamples() throws {
        let service = LeanAngleService(
            provider: StubMotionProvider(),
            smoothingAlpha: 1.0
        )
        _ = service.encode(MotionSample(
            scenarioTime: 0, gravityX: -0.5, gravityY: -0.8660254, gravityZ: 0
        )) // +30 right
        _ = service.encode(MotionSample(
            scenarioTime: 0.1, gravityX: 0.7071, gravityY: -0.7071, gravityZ: 0
        )) // -45 left
        let blob = service.encode(MotionSample(
            scenarioTime: 0.2, gravityX: 0, gravityY: -1, gravityZ: 0
        )) // back to 0
        let payload = try ScreenPayloadCodec.decode(XCTUnwrap(blob))
        guard case .leanAngle(let data, _) = payload else { XCTFail(); return }
        XCTAssertEqual(Int(data.currentLeanDegX10), 0)
        XCTAssertEqual(Int(data.maxLeftLeanDegX10), 450)
        XCTAssertEqual(Int(data.maxRightLeanDegX10), 300)
    }

    func test_resetClearsAccumulatedState() throws {
        let service = LeanAngleService(
            provider: StubMotionProvider(),
            smoothingAlpha: 1.0
        )
        _ = service.encode(MotionSample(
            scenarioTime: 0, gravityX: -0.5, gravityY: -0.8660254, gravityZ: 0
        ))
        XCTAssertEqual(service.currentCalculator.maxRightLeanDegrees, 30, accuracy: 0.5)
        service.reset()
        XCTAssertEqual(service.currentCalculator.maxRightLeanDegrees, 0)
        XCTAssertEqual(service.currentCalculator.currentLeanDegrees, 0)
        XCTAssertEqual(service.currentCalculator.samplesSeen, 0)
    }

    func test_streamReceivesEncodedPayloads() async throws {
        let mock = MockMotionProvider()
        let service = LeanAngleService(provider: mock, smoothingAlpha: 1.0)
        service.start()

        var iterator = service.encodedPayloads.makeAsyncIterator()
        mock.emit(MotionSample(
            scenarioTime: 0, gravityX: -0.5, gravityY: -0.8660254, gravityZ: 0
        ))

        let blob = await iterator.next()
        let payload = try ScreenPayloadCodec.decode(XCTUnwrap(blob))
        guard case .leanAngle(let data, _) = payload else {
            XCTFail("stream did not deliver a leanAngle payload")
            return
        }
        XCTAssertEqual(Int(data.currentLeanDegX10), 300)
        service.stop()
    }
}

private final class StubMotionProvider: MotionProvider, @unchecked Sendable {
    let samples: AsyncStream<MotionSample>
    init() { self.samples = AsyncStream { _ in } }
    func start() async {}
    func stop() async {}
}
