import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``CallEvent`` values from any ``CallObserver`` into encoded
/// BLE payloads for the `incomingCall` screen, and exposes them as an
/// ``AsyncStream`` of `Data` blobs ready to write to the peripheral.
///
/// Key behavior: on `incoming`/`connected`, the payload is encoded with the
/// `.alert` header flag set. On `ended`, the flag is cleared. The ALERT
/// flag in the header signals the ESP32 screen FSM to treat the payload as
/// a priority overlay.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. Calling ``stop()`` terminates both the
/// forwarding task and the output stream.
public final class CallAlertService: @unchecked Sendable {
    private let observer: any CallObserver
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>

    private let lock = NSLock()
    private var forwardingTask: Task<Void, Never>?

    public init(observer: any CallObserver) {
        self.observer = observer
        self.encodedPayloads = channel.makeStream()
    }

    public func start() {
        lock.lock()
        guard forwardingTask == nil else {
            lock.unlock()
            return
        }
        let stream = observer.events
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

    func encode(_ event: CallEvent) -> Data? {
        let callState: IncomingCallData.CallStateWire
        switch event.state {
        case .incoming: callState = .incoming
        case .connected: callState = .connected
        case .ended: callState = .ended
        }

        let callerHandle = Self.truncateUTF8(
            event.callerHandle,
            maxByteCount: IncomingCallData.callerHandleFieldLength - 1
        )

        let callData = IncomingCallData(
            callState: callState,
            callerHandle: callerHandle
        )

        let flags = callData.recommendedFlags

        do {
            return try ScreenPayloadCodec.encode(
                .incomingCall(callData, flags: flags)
            )
        } catch {
            return nil
        }
    }

    /// Truncates `value` to at most `maxByteCount` UTF-8 bytes without
    /// splitting a multi-byte scalar.
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
