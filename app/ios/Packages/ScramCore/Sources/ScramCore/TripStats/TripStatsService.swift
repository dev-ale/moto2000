import Foundation
import BLEProtocol
import RideSimulatorKit

/// Subscribes to a ``LocationProvider`` and exposes an ``AsyncStream`` of
/// encoded `tripStats` BLE payloads driven by a rolling
/// ``TripStatsAccumulator``.
///
/// **Emission cadence:** the service emits one encoded payload **per
/// incoming sample**, not on a fixed wall-clock interval. The rationale
/// is that scenario replay drives sample arrival deterministically, and
/// emitting on every sample makes integration tests trivial — payload
/// count == sample count. The downstream BLE characteristic is GATT
/// notify, so the cost of an extra notify per sample is negligible.
///
/// One-shot lifecycle: call ``start()`` once, drain ``payloads`` once,
/// optionally call ``reset()`` to zero the running totals (used by the
/// future "new trip" button) and ``stop()`` to terminate the stream.
public final class TripStatsService: @unchecked Sendable {
    private let provider: any LocationProvider
    private let channel = TripStatsPayloadChannel()
    public let payloads: AsyncStream<Data>

    private let lock = NSLock()
    private var accumulator = TripStatsAccumulator()
    private var forwardingTask: Task<Void, Never>?

    public init(provider: any LocationProvider) {
        self.provider = provider
        self.payloads = channel.makeStream()
    }

    /// Start consuming samples. Idempotent: a second call while a
    /// forwarding task is alive is a no-op.
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

    /// Zeros the running accumulator. Subsequent samples are treated as
    /// the start of a new trip — the next sample seeds `lastSample` so
    /// distance/time count from there.
    public func reset() {
        lock.lock()
        accumulator = TripStatsAccumulator()
        lock.unlock()
    }

    /// Snapshot of the current accumulator. Used by tests and any future
    /// caller that wants to render stats without re-decoding the wire
    /// payload.
    public var currentSnapshot: TripStatsData {
        lock.lock()
        defer { lock.unlock() }
        return accumulator.snapshot
    }

    /// Synchronous ingest entrypoint exposed for unit tests that need
    /// to drive the service without spinning up the async forwarding
    /// task. Production callers should always go through ``start()``.
    func ingest(_ sample: LocationSample) {
        lock.lock()
        accumulator = accumulator.ingesting(sample)
        let snapshot = accumulator.snapshot
        lock.unlock()
        do {
            let blob = try ScreenPayloadCodec.encode(.tripStats(snapshot, flags: []))
            channel.emit(blob)
        } catch {
            // snapshot clamping guarantees encode never throws — drop
            // on the impossible path so a release build keeps moving.
        }
    }
}

/// Single-producer broadcaster for encoded trip-stats payloads. Mirrors
/// `PayloadChannel` from `SpeedHeadingService` so the two services stay
/// independent — sharing one channel between services would couple
/// their lifecycles.
final class TripStatsPayloadChannel: @unchecked Sendable {
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
