import Foundation

/// A loopback ``BLETransport`` that spawns the C host simulator as a
/// subprocess and pipes the encoded BLE payload into its standard input,
/// producing a PNG on disk at `outputURL`.
///
/// This is the subprocess flavour of the transport (as opposed to a
/// file-based flavour). The subprocess design is easier to test because:
///
/// - The binary is the exact same one CI runs for snapshot tests, so the
///   iOS + firmware halves of the loop share one renderer with zero code
///   duplication.
/// - The "command to run" is a single `URL` a test can point at the build
///   output of `hardware/firmware/host-sim/build/`. No filesystem watcher,
///   no polling, no race on "has the sim finished".
/// - Exit codes bubble up cleanly; the test can assert on them.
///
/// The downside is that the simulator is a desktop-only executable, so
/// this transport is gated to macOS and Linux. iOS builds see
/// ``HostSimulatorTransportError/unsupportedPlatform`` if they ever try to
/// use it. Real on-device runs use a (future) ``CoreBluetoothTransport``.
public struct HostSimulatorBLETransport: BLETransport {
    /// Path to `scramscreen-host-sim`. For unit tests this is usually set
    /// via the `SCRAMSCREEN_HOST_SIM` environment variable; see
    /// ``locateFromEnvironment()`` below.
    public let executableURL: URL

    /// Where the rendered PNG should be written. The transport overwrites
    /// this file on every ``send(_:)`` call.
    public let outputURL: URL

    public init(executableURL: URL, outputURL: URL) {
        self.executableURL = executableURL
        self.outputURL = outputURL
    }

    /// Convenience constructor that resolves the executable from the
    /// `SCRAMSCREEN_HOST_SIM` environment variable. Returns `nil` when the
    /// variable is unset or points at a file that does not exist — tests
    /// use that to skip themselves cleanly when the simulator has not been
    /// built yet.
    public static func locateFromEnvironment(outputURL: URL)
        -> HostSimulatorBLETransport?
    {
        #if os(macOS) || os(Linux)
        guard let raw = ProcessInfo.processInfo.environment["SCRAMSCREEN_HOST_SIM"] else {
            return nil
        }
        let url = URL(fileURLWithPath: raw)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return HostSimulatorBLETransport(executableURL: url, outputURL: outputURL)
        #else
        return nil
        #endif
    }

    public func send(_ payload: Data) async throws {
        #if os(macOS) || os(Linux)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw HostSimulatorTransportError.simulatorNotFound(path: executableURL.path)
        }
        try await Self.run(
            executableURL: executableURL,
            outputURL: outputURL,
            payload: payload
        )
        #else
        _ = payload
        throw HostSimulatorTransportError.unsupportedPlatform
        #endif
    }

    #if os(macOS) || os(Linux)
    private static func run(
        executableURL: URL,
        outputURL: URL,
        payload: Data
    ) async throws {
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--out", outputURL.path]

            let stdinPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardError = stderrPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
                return
            }

            // Feed the payload and close stdin so the simulator sees EOF.
            let stdinHandle = stdinPipe.fileHandleForWriting
            do {
                try stdinHandle.write(contentsOf: payload)
                try stdinHandle.close()
            } catch {
                process.terminate()
                cont.resume(throwing: error)
                return
            }

            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData: Data =
                    ((try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil)
                    ?? Data()
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                cont.resume(
                    throwing: HostSimulatorTransportError.simulatorFailed(
                        status: process.terminationStatus,
                        stderr: stderr
                    )
                )
                return
            }
            cont.resume(returning: ())
        }
    }
    #endif
}
