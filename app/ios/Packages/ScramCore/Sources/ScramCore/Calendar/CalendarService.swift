import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``CalendarEvent`` values from any ``CalendarProvider`` into
/// encoded BLE `appointment` payloads and exposes them as an ``AsyncStream``
/// of `Data` blobs ready to write to the peripheral.
///
/// Transform rules:
///  - `startsInSeconds` is divided by 60 and rounded to produce
///    `startsInMinutes`. The result is clamped to `-1440..=10080`.
///  - `title` is truncated to 31 UTF-8 bytes (leaves room for the
///    null terminator in the 32-byte field). Truncation is byte-accurate
///    and will not split a multi-byte UTF-8 sequence.
///  - `location` is truncated to 23 UTF-8 bytes (same pattern for the
///    24-byte field).
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. Calling ``stop()`` terminates both the
/// forwarding task and the output stream.
public final class CalendarService: PayloadService, @unchecked Sendable {
    public static let maxTitleUTF8Bytes: Int = 31
    public static let maxLocationUTF8Bytes: Int = 23

    private let provider: any CalendarProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    private let lock = NSLock()
    private var forwardingTask: Task<Void, Never>?

    public init(provider: any CalendarProvider) {
        self.provider = provider
        self.encodedPayloads = channel.makeStream()
    }

    public func start() {
        lock.lock()
        guard forwardingTask == nil else {
            lock.unlock()
            return
        }
        let stream = provider.events
        forwardingTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if let data = self.encode(event) {
                    self.channel.emit(data)
                }
            }
            self?.channel.finish()
        }
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let task = forwardingTask
        forwardingTask = nil
        lock.unlock()
        task?.cancel()
        channel.finish()
    }

    // MARK: - Transform

    func encode(_ event: CalendarEvent) -> Data? {
        let minutes = Self.secondsToMinutesClamped(event.startsInSeconds)
        let title = Self.truncateUTF8(event.title, maxByteCount: Self.maxTitleUTF8Bytes)
        let location = Self.truncateUTF8(event.location, maxByteCount: Self.maxLocationUTF8Bytes)
        let data = AppointmentData(
            startsInMinutes: minutes,
            title: title,
            location: location
        )
        do {
            return try ScreenPayloadCodec.encode(.appointment(data, flags: []))
        } catch {
            return nil
        }
    }

    /// Converts seconds to minutes, rounding toward zero, and clamps to
    /// the wire range `-1440..=10080`.
    static func secondsToMinutesClamped(_ seconds: Double) -> Int16 {
        let minutes = (seconds / 60.0).rounded(.towardZero)
        let clamped = min(max(minutes, Double(AppointmentData.minStartsInMinutes)),
                          Double(AppointmentData.maxStartsInMinutes))
        return Int16(clamped)
    }

    /// Truncates `value` to at most `maxByteCount` UTF-8 bytes without
    /// splitting a multi-byte scalar. Returns the (possibly unchanged)
    /// truncated string.
    static func truncateUTF8(_ value: String, maxByteCount: Int) -> String {
        if value.utf8.count <= maxByteCount {
            return value
        }
        var result = ""
        var total = 0
        for scalar in value.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if total + scalarBytes > maxByteCount {
                break
            }
            result.unicodeScalars.append(scalar)
            total += scalarBytes
        }
        return result
    }
}
