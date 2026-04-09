import XCTest
@testable import ScenarioToVideo

final class VideoEncoderTests: XCTestCase {
    func testArgumentList() {
        let args = VideoEncoder.argumentList(
            framePattern: "frame-%06d.png",
            fps: 1,
            outputPath: "/tmp/out.mp4"
        )
        XCTAssertEqual(args, [
            "-y",
            "-framerate", "1",
            "-i", "frame-%06d.png",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "medium",
            "/tmp/out.mp4",
        ])
    }

    func testArgumentListRespectsFps() {
        let args = VideoEncoder.argumentList(
            framePattern: "f.png", fps: 30, outputPath: "x"
        )
        XCTAssertEqual(args[2], "30")
    }

    func testAbsolutePathMissingRaises() {
        XCTAssertThrowsError(
            try VideoEncoder.resolveExecutable("/nope/ffmpeg/does/not/exist")
        ) { err in
            guard case VideoEncoderError.ffmpegNotFound = err else {
                return XCTFail("expected ffmpegNotFound, got \(err)")
            }
        }
    }

    func testAbsolutePathPresentResolves() throws {
        // /bin/sh is a reliable executable on macOS and Linux.
        let url = try VideoEncoder.resolveExecutable("/bin/sh")
        XCTAssertEqual(url.path, "/bin/sh")
    }
}
