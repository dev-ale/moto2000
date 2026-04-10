import Foundation
import BLEProtocol

/// Abstraction over the system clock for testability.
public protocol ClockProvider: Sendable {
    func now() -> Date
    func timeZone() -> TimeZone
    func is24Hour() -> Bool
}

/// Default implementation that reads from the real system clock and locale.
public struct SystemClockProvider: ClockProvider, Sendable {
    public init() {}

    public func now() -> Date { Date() }
    public func timeZone() -> TimeZone { TimeZone.current }
    public func is24Hour() -> Bool {
        true
    }
}

/// Produces encoded BLE `clock` payloads every 30 seconds (and immediately
/// on start) and exposes them as an ``AsyncStream`` of `Data` blobs ready
/// to write to the peripheral.
///
/// The service reads the current time, timezone offset, and 24-hour
/// preference from a ``ClockProvider``, builds a ``ClockData`` payload,
/// encodes it through ``ScreenPayloadCodec``, and emits the raw bytes.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. Calling ``stop()`` terminates both the
/// ticking task and the output stream.
public final class ClockService: @unchecked Sendable {
    /// Tick interval in seconds.
    public static let tickInterval: TimeInterval = 30

    private let provider: any ClockProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>

    private let lock = NSLock()
    private var tickTask: Task<Void, Never>?

    /// Tick interval override for testing. When non-nil, this interval is
    /// used instead of ``tickInterval``.
    private let intervalOverride: TimeInterval?

    public init(provider: any ClockProvider, tickInterval: TimeInterval? = nil) {
        self.provider = provider
        self.intervalOverride = tickInterval
        self.encodedPayloads = channel.makeStream()
    }

    /// Start producing clock payloads. Emits immediately, then every
    /// ``tickInterval`` seconds. Idempotent: calling twice while a tick
    /// task is alive has no effect.
    public func start() {
        lock.lock()
        guard tickTask == nil else {
            lock.unlock()
            return
        }
        let interval = intervalOverride ?? Self.tickInterval
        tickTask = Task { [weak self] in
            // Emit immediately on start.
            if let data = self?.encodeTick() {
                self?.channel.emit(data)
            }

            // Then tick every `interval` seconds.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard let self else { return }
                if let data = self.encodeTick() {
                    self.channel.emit(data)
                }
            }
        }
        lock.unlock()
    }

    /// Stop ticking and terminate ``encodedPayloads``.
    public func stop() {
        lock.lock()
        let task = tickTask
        tickTask = nil
        lock.unlock()
        task?.cancel()
        channel.finish()
    }

    // MARK: - Encode

    /// Build and encode a single clock payload from the current provider state.
    func encodeTick() -> Data? {
        let date = provider.now()
        let tz = provider.timeZone()
        let is24h = provider.is24Hour()

        let unixTime = Int64(date.timeIntervalSince1970)
        let tzOffsetSeconds = tz.secondsFromGMT(for: date)
        let tzOffsetMinutes = Int16(clamping: tzOffsetSeconds / 60)

        let clockData = ClockData(
            unixTime: unixTime,
            tzOffsetMinutes: tzOffsetMinutes,
            is24Hour: is24h
        )

        do {
            return try ScreenPayloadCodec.encode(.clock(clockData, flags: []))
        } catch {
            return nil
        }
    }
}
