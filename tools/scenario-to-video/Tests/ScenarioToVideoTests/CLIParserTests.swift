import XCTest
@testable import ScenarioToVideo

final class CLIParserTests: XCTestCase {
    func testRequiredFlags() throws {
        let opts = try CLIParser.parse([
            "--scenario", "/tmp/s.json",
            "--host-sim", "/tmp/sim",
            "--out", "/tmp/out.mp4",
        ])
        XCTAssertEqual(opts.scenarioPath, "/tmp/s.json")
        XCTAssertEqual(opts.hostSimPath, "/tmp/sim")
        XCTAssertEqual(opts.outputPath, "/tmp/out.mp4")
        XCTAssertEqual(opts.ffmpegPath, "ffmpeg")
        XCTAssertEqual(opts.fps, 1)
        XCTAssertFalse(opts.keepFrames)
        XCTAssertFalse(opts.verbose)
        XCTAssertNil(opts.screen)
    }

    func testAllFlags() throws {
        let opts = try CLIParser.parse([
            "--scenario", "a.json",
            "--host-sim", "sim",
            "--out", "o.mp4",
            "--ffmpeg", "/opt/ffmpeg",
            "--screen", "clock",
            "--fps", "30",
            "--keep-frames",
            "--verbose",
        ])
        XCTAssertEqual(opts.ffmpegPath, "/opt/ffmpeg")
        XCTAssertEqual(opts.screen, "clock")
        XCTAssertEqual(opts.fps, 30)
        XCTAssertTrue(opts.keepFrames)
        XCTAssertTrue(opts.verbose)
    }

    func testMissingScenarioRaises() {
        XCTAssertThrowsError(try CLIParser.parse([
            "--host-sim", "sim", "--out", "o.mp4",
        ])) { err in
            guard let cli = err as? CLIError else { return XCTFail() }
            XCTAssertTrue(cli.message.contains("--scenario"))
        }
    }

    func testUnknownArgument() {
        XCTAssertThrowsError(try CLIParser.parse([
            "--scenario", "a", "--host-sim", "b", "--out", "c", "--bogus",
        ])) { err in
            guard let cli = err as? CLIError else { return XCTFail() }
            XCTAssertTrue(cli.message.contains("unknown"))
        }
    }

    func testInvalidFps() {
        XCTAssertThrowsError(try CLIParser.parse([
            "--scenario", "a", "--host-sim", "b", "--out", "c",
            "--fps", "zero",
        ]))
    }

    func testHelpExitsZero() {
        XCTAssertThrowsError(try CLIParser.parse(["--help"])) { err in
            guard let cli = err as? CLIError else { return XCTFail() }
            XCTAssertEqual(cli.exitCode, 0)
        }
    }

    func testResolveScreen() throws {
        XCTAssertEqual(try CLIParser.resolveScreen(nil), .speedHeading)
        XCTAssertEqual(try CLIParser.resolveScreen("speed"), .speedHeading)
        XCTAssertEqual(try CLIParser.resolveScreen("SPEED"), .speedHeading)
        XCTAssertEqual(try CLIParser.resolveScreen("clock"), .clock)
        XCTAssertEqual(
            try CLIParser.resolveScreen("rotate"),
            .rotating(holdSeconds: 10)
        )
        XCTAssertThrowsError(try CLIParser.resolveScreen("weather"))
    }
}
