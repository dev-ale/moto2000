import Foundation

/// Errors the CLI layer surfaces to the user. Keeps `main.swift` trivially
/// small and lets tests assert on error messages without catching generic
/// `Error`.
public struct CLIError: Error, Equatable {
    public var message: String
    public var exitCode: Int32

    public init(_ message: String, exitCode: Int32 = 2) {
        self.message = message
        self.exitCode = exitCode
    }
}

/// Parsed command-line options. `CLIParser` populates this from argv and
/// the runner consumes it.
public struct CLIOptions: Equatable, Sendable {
    public var scenarioPath: String
    public var hostSimPath: String
    public var ffmpegPath: String
    public var outputPath: String
    public var screen: String?
    public var fps: Int
    public var keepFrames: Bool
    public var verbose: Bool

    public init(
        scenarioPath: String,
        hostSimPath: String,
        ffmpegPath: String,
        outputPath: String,
        screen: String?,
        fps: Int,
        keepFrames: Bool,
        verbose: Bool
    ) {
        self.scenarioPath = scenarioPath
        self.hostSimPath = hostSimPath
        self.ffmpegPath = ffmpegPath
        self.outputPath = outputPath
        self.screen = screen
        self.fps = fps
        self.keepFrames = keepFrames
        self.verbose = verbose
    }
}

/// Hand-rolled argv parser. Kept intentionally tiny — the project does not
/// depend on swift-argument-parser to keep the dependency surface minimal.
public enum CLIParser {
    public static let usage: String = """
        Usage: scenario-to-video --scenario <path> --host-sim <path> --out <path> [options]

        Required:
          --scenario <path>     Path to a scenario JSON file.
          --host-sim <path>     Path to the scramscreen-host-sim executable.
          --out <path>          Path to the output MP4.

        Options:
          --ffmpeg <path>       Path to ffmpeg (default: "ffmpeg" from PATH).
          --screen <name>       Force a single screen ("speed", "clock"). Default: speed.
          --fps <n>             Frames per simulated second (default: 1).
          --keep-frames         Don't delete the intermediate PNG directory.
          --verbose             Log every frame to stderr.
          -h, --help            Print this help.
        """

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var scenarioPath: String?
        var hostSimPath: String?
        var outputPath: String?
        var ffmpegPath = "ffmpeg"
        var screen: String?
        var fps: Int = 1
        var keepFrames = false
        var verbose = false

        var i = 0
        func nextValue(for flag: String) throws -> String {
            i += 1
            guard i < arguments.count else {
                throw CLIError("missing value for \(flag)")
            }
            return arguments[i]
        }

        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "-h", "--help":
                throw CLIError(usage, exitCode: 0)
            case "--scenario":
                scenarioPath = try nextValue(for: arg)
            case "--host-sim":
                hostSimPath = try nextValue(for: arg)
            case "--out":
                outputPath = try nextValue(for: arg)
            case "--ffmpeg":
                ffmpegPath = try nextValue(for: arg)
            case "--screen":
                screen = try nextValue(for: arg)
            case "--fps":
                let v = try nextValue(for: arg)
                guard let n = Int(v), n > 0 else {
                    throw CLIError("--fps must be a positive integer (got '\(v)')")
                }
                fps = n
            case "--keep-frames":
                keepFrames = true
            case "--verbose":
                verbose = true
            default:
                throw CLIError("unknown argument: \(arg)\n\n\(usage)")
            }
            i += 1
        }

        guard let scenarioPath else { throw CLIError("--scenario is required\n\n\(usage)") }
        guard let hostSimPath else { throw CLIError("--host-sim is required\n\n\(usage)") }
        guard let outputPath else { throw CLIError("--out is required\n\n\(usage)") }

        return CLIOptions(
            scenarioPath: scenarioPath,
            hostSimPath: hostSimPath,
            ffmpegPath: ffmpegPath,
            outputPath: outputPath,
            screen: screen,
            fps: fps,
            keepFrames: keepFrames,
            verbose: verbose
        )
    }

    /// Resolve the user-facing `--screen` string into a ``FrameScreen``.
    /// When unspecified, the default is `.speedHeading` — rotating through
    /// multiple screens is a documented TODO, not yet implemented.
    public static func resolveScreen(_ name: String?) throws -> FrameScreen {
        guard let raw = name?.lowercased() else {
            return .speedHeading
        }
        switch raw {
        case "speed", "speed-heading", "speedheading", "0x02":
            return .speedHeading
        case "clock", "0x0d":
            return .clock
        case "rotate", "rotating":
            return .rotating(holdSeconds: 10)
        default:
            throw CLIError("unsupported --screen value '\(raw)' (expected: speed, clock, rotate)")
        }
    }
}
