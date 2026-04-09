import Foundation

public enum VideoEncoderError: Error, Equatable {
    case ffmpegNotFound(path: String)
    case ffmpegFailed(status: Int32, stderr: String)
}

/// Wraps `ffmpeg` as a subprocess. Only responsibility: build the argument
/// list and spawn the process. The unit tests exercise ``argumentList(...)``
/// without actually invoking ffmpeg — end-to-end encoding is a manual-only
/// step because CI doesn't have ffmpeg installed.
public struct VideoEncoder: Sendable {
    public let ffmpegPath: String

    public init(ffmpegPath: String = "ffmpeg") {
        self.ffmpegPath = ffmpegPath
    }

    /// Pure function that returns the ffmpeg argv given the parameters.
    /// Exposed so unit tests can assert on it without touching the disk.
    public static func argumentList(
        framePattern: String,
        fps: Int,
        outputPath: String
    ) -> [String] {
        return [
            "-y",
            "-framerate", String(fps),
            "-i", framePattern,
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "medium",
            outputPath,
        ]
    }

    /// Spawn ffmpeg. `framePattern` is a printf-style name like
    /// `frame-%06d.png` that is resolved relative to `frameDirectory`.
    public func encode(
        frameDirectory: URL,
        framePattern: String,
        fps: Int,
        outputURL: URL
    ) throws {
        let resolvedFfmpeg = try Self.resolveExecutable(ffmpegPath)

        let args = Self.argumentList(
            framePattern: framePattern,
            fps: fps,
            outputPath: outputURL.path
        )

        let process = Process()
        process.executableURL = resolvedFfmpeg
        process.arguments = args
        process.currentDirectoryURL = frameDirectory
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data: Data =
                ((try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw VideoEncoderError.ffmpegFailed(
                status: process.terminationStatus,
                stderr: text
            )
        }
    }

    /// Locate the ffmpeg binary. Accepts either an absolute path or a bare
    /// name that should be resolved against `$PATH`.
    static func resolveExecutable(_ path: String) throws -> URL {
        if path.contains("/") {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw VideoEncoderError.ffmpegNotFound(path: path)
            }
            return url
        }
        // `which`-style lookup against $PATH.
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in env.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir))
                .appendingPathComponent(path)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw VideoEncoderError.ffmpegNotFound(path: path)
    }
}
