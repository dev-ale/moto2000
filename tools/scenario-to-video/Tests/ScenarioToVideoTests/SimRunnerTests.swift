import XCTest
import BLEProtocol
@testable import ScenarioToVideo

final class SimRunnerTests: XCTestCase {
    func testMissingBinaryThrows() throws {
        let runner = SimRunner(
            executableURL: URL(fileURLWithPath: "/does/not/exist/scramscreen-host-sim")
        )
        let frame = Frame(
            timeSeconds: 0,
            payload: .speedHeading(
                SpeedHeadingData(
                    speedKmhX10: 0,
                    headingDegX10: 0,
                    altitudeMeters: 0,
                    temperatureCelsiusX10: 0
                ),
                flags: []
            )
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sr-\(UUID().uuidString).png")
        XCTAssertThrowsError(try runner.renderSync(frame: frame, to: tmp))
    }

    /// Only runs if the host-sim binary has been built and exported through
    /// the `SCRAMSCREEN_HOST_SIM` env var — same opt-in pattern as
    /// `RideSimulatorKit`'s BLE transport tests.
    func testRealBinaryIfAvailable() throws {
        guard
            let simPath = ProcessInfo.processInfo.environment["SCRAMSCREEN_HOST_SIM"],
            FileManager.default.fileExists(atPath: simPath)
        else {
            throw XCTSkip("SCRAMSCREEN_HOST_SIM not set; skipping real-subprocess test")
        }
        let runner = SimRunner(executableURL: URL(fileURLWithPath: simPath))
        let frame = Frame(
            timeSeconds: 0,
            payload: .speedHeading(
                SpeedHeadingData(
                    speedKmhX10: 500,
                    headingDegX10: 900,
                    altitudeMeters: 260,
                    temperatureCelsiusX10: 200
                ),
                flags: []
            )
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sr-\(UUID().uuidString).png")
        try runner.renderSync(frame: frame, to: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        try? FileManager.default.removeItem(at: tmp)
    }
}
