import Foundation
import BLEProtocol
import RideSimulatorKit

public enum SimRunnerError: Error, Equatable {
    /// The bridging task resolved the semaphore without writing a result.
    /// Should never happen in practice — present only so the switch is
    /// exhaustive without a `fatalError`.
    case transportProducedNoResult
}

/// Boxed `Result` that lets a synchronous caller observe the outcome of an
/// `async` task. Uses an `NSLock` for safe cross-thread visibility — the
/// calling thread waits on a semaphore and then reads `.value` after the
/// child `Task` has written it.
final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Result<Void, any Error>?
    var value: Result<Void, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ v: Result<Void, any Error>) {
        lock.lock()
        _value = v
        lock.unlock()
    }
}

/// Thin wrapper around ``HostSimulatorBLETransport`` that turns a
/// ``Frame`` into a PNG on disk. The subprocess-spawning logic lives in
/// ``RideSimulatorKit`` — duplicating it here would be a maintenance hazard.
public struct SimRunner: Sendable {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    /// Synchronous wrapper that drives the async transport. The tool is a
    /// CLI so a per-frame semaphore-bridged box is simpler than building a
    /// `@main` async entry point just to get a sequential loop.
    public func renderSync(frame: Frame, to outputURL: URL) throws {
        let bytes = try ScreenPayloadCodec.encode(frame.payload)
        let transport = HostSimulatorBLETransport(
            executableURL: executableURL,
            outputURL: outputURL
        )

        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                try await transport.send(bytes)
                box.set(.success(()))
            } catch {
                box.set(.failure(error))
            }
            sem.signal()
        }
        sem.wait()
        switch box.value {
        case .success:
            return
        case .failure(let err):
            throw err
        case .none:
            throw SimRunnerError.transportProducedNoResult
        }
    }
}
