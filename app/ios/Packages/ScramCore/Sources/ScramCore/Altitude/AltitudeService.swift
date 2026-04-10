import Foundation
import BLEProtocol
import RideSimulatorKit

/// Subscribes to a ``LocationProvider`` and emits encoded `altitude`
/// BLE payloads containing the elevation profile history.
///
/// Similar lifecycle to ``TripStatsService``: emits one payload per
/// incoming sample, one-shot start/stop.
public final class AltitudeService: @unchecked Sendable {
    private let provider: any LocationProvider
    private let channel = AltitudePayloadChannel()
    public let payloads: AsyncStream<Data>

    private let lock = NSLock()
    private var buffer = ElevationHistoryBuffer()
    private var forwardingTask: Task<Void, Never>?

    public init(provider: any LocationProvider) {
        self.provider = provider
        self.payloads = channel.makeStream()
    }

    /// Start consuming location samples. Idempotent.
    public func start() {
        lock.lock()
        let alreadyStarted = forwardingTask != nil
        lock.unlock()
        if alreadyStarted { return }

        let stream = provider.samples
        let task = Task { [weak self] in
            for await sample in stream {
                guard let self else { return }
                self.ingest(sample)
            }
            self?.channel.finish()
        }
        lock.lock()
        forwardingTask = task
        lock.unlock()
    }

    /// Cancels forwarding and finishes the payload stream.
    public func stop() {
        lock.lock()
        let task = forwardingTask
        forwardingTask = nil
        lock.unlock()
        task?.cancel()
        channel.finish()
    }

    /// Zeros the buffer. Used for "new trip" flows.
    public func reset() {
        lock.lock()
        buffer = ElevationHistoryBuffer()
        lock.unlock()
    }

    /// Current snapshot for test inspection.
    public var currentSnapshot: AltitudeProfileData {
        lock.lock()
        defer { lock.unlock() }
        return buffer.snapshot
    }

    /// Synchronous ingest for unit tests.
    func ingest(_ sample: LocationSample) {
        lock.lock()
        buffer = buffer.ingesting(sample.altitudeMeters)
        let snapshot = buffer.snapshot
        lock.unlock()
        do {
            let blob = try ScreenPayloadCodec.encode(.altitude(snapshot, flags: []))
            channel.emit(blob)
        } catch {
            // snapshot clamping guarantees encode never throws
        }
    }
}

/// Single-producer broadcaster for encoded altitude payloads.
final class AltitudePayloadChannel: @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<Data> {
        AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: Data) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(element)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
