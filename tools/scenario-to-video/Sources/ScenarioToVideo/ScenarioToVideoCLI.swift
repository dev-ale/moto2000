import Foundation
import BLEProtocol
import RideSimulatorKit

/// Top-level entry point called from `main.swift`. Parses argv, loads the
/// scenario, walks the timeline through ``FrameBuilder`` + ``SimRunner``,
/// and hands the resulting PNGs to ``VideoEncoder``.
public enum ScenarioToVideoCLI {
    public static func run(arguments: [String]) throws {
        let options = try CLIParser.parse(arguments)
        let frameScreen = try CLIParser.resolveScreen(options.screen)

        let scenarioURL = URL(fileURLWithPath: options.scenarioPath)
        let scenario: Scenario
        do {
            scenario = try ScenarioLoader.load(from: scenarioURL)
        } catch {
            throw CLIError("failed to load scenario at \(options.scenarioPath): \(error)")
        }

        let builder = FrameBuilder(scenario: scenario, screen: frameScreen, stepSeconds: 1.0)

        if options.hexStream {
            try runHexStream(builder: builder, verbose: options.verbose)
            return
        }

        // Working directory for intermediate PNGs.
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(
            "scenario-to-video-\(UUID().uuidString)", isDirectory: true
        )
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let hostSimURL = URL(fileURLWithPath: options.hostSimPath)
        let simRunner = SimRunner(executableURL: hostSimURL)

        if options.verbose {
            FileHandle.standardError.write(
                Data("scenario: \(scenario.name) (\(scenario.durationSeconds)s)\n".utf8)
            )
            FileHandle.standardError.write(
                Data("frames: \(builder.frameCount) → \(workDir.path)\n".utf8)
            )
        }

        var framePaths: [URL] = []
        framePaths.reserveCapacity(builder.frameCount)
        for i in 0..<builder.frameCount {
            let frame = try builder.frame(at: i)
            let frameURL = workDir.appendingPathComponent(
                String(format: "frame-%06d.png", i)
            )
            do {
                try simRunner.renderSync(frame: frame, to: frameURL)
            } catch {
                throw CLIError("host-sim failed on frame \(i): \(error)")
            }
            if options.verbose {
                FileHandle.standardError.write(
                    Data("frame \(i) → \(frameURL.lastPathComponent)\n".utf8)
                )
            }
            framePaths.append(frameURL)
        }

        let encoder = VideoEncoder(ffmpegPath: options.ffmpegPath)
        do {
            try encoder.encode(
                frameDirectory: workDir,
                framePattern: "frame-%06d.png",
                fps: options.fps,
                outputURL: URL(fileURLWithPath: options.outputPath)
            )
        } catch {
            throw CLIError("ffmpeg failed: \(error)")
        }

        if !options.keepFrames {
            try? fm.removeItem(at: workDir)
        } else if options.verbose {
            FileHandle.standardError.write(
                Data("kept frames at \(workDir.path)\n".utf8)
            )
        }

        FileHandle.standardOutput.write(
            Data("wrote \(options.outputPath)\n".utf8)
        )
    }

    /// Emit hex-encoded BLE payloads to stdout with real-time pacing.
    /// Emits ALL screen payloads every tick so the simulator can cache
    /// them and let the user switch interactively with arrow keys.
    /// Pipe into `scramscreen-lvgl-sim --live` for a live display.
    private static func runHexStream(builder: FrameBuilder, verbose: Bool) throws {
        // Build a FrameBuilder per screen so we can emit all of them.
        let allScreens: [FrameScreen] = FrameScreen.allSingle
        let builders = allScreens.map {
            FrameBuilder(scenario: builder.scenario, screen: $0, stepSeconds: builder.stepSeconds)
        }

        let frameCount = builder.frameCount
        if verbose {
            FileHandle.standardError.write(
                Data("hex-stream: \(frameCount) frames × \(allScreens.count) screens, \(builder.scenario.durationSeconds)s\n".utf8)
            )
            FileHandle.standardError.write(
                Data("Use ← → arrow keys to switch screens, N for night mode, Q to quit\n".utf8)
            )
        }

        let start = Date()
        for i in 0..<frameCount {
            let t = Double(i) * builder.stepSeconds

            // Emit one payload per screen at this time step.
            for b in builders {
                let payload = b.buildPayload(screen: b.screen, at: t)
                let bytes = try ScreenPayloadCodec.encode(payload)
                let hex = bytes.map { String(format: "%02x", $0) }.joined()
                FileHandle.standardOutput.write(Data("\(hex)\n".utf8))
            }

            if verbose && i % 10 == 0 {
                FileHandle.standardError.write(
                    Data("t=\(String(format: "%.0f", t))s\n".utf8)
                )
            }

            // Pace output in real time.
            if i + 1 < frameCount {
                let nextT = Double(i + 1) * builder.stepSeconds
                let elapsed = Date().timeIntervalSince(start)
                let sleepTime = nextT - elapsed
                if sleepTime > 0 {
                    Thread.sleep(forTimeInterval: sleepTime)
                }
            }
        }
    }
}
