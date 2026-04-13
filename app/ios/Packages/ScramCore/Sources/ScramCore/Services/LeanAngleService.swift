import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``MotionSample`` values from any ``MotionProvider`` into
/// encoded BLE payloads for the `leanAngle` screen, and exposes them as
/// an ``AsyncStream`` of `Data` blobs ready to write to the peripheral.
///
/// One-shot pipeline: call ``start()`` once, read ``encodedPayloads`` once,
/// then call ``stop()``. Same shape as ``SpeedHeadingService``.
public final class LeanAngleService: PayloadService, @unchecked Sendable {
    private let provider: any MotionProvider
    private let channel = PayloadChannel()
    private let lock = NSLock()
    private var calculator: LeanAngleCalculator
    private var forwardingTask: Task<Void, Never>?
    public let encodedPayloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    /// Zero-offset captured by the rider when they hold BOOT on the
    /// display. Subtracted from every subsequent reading so the bike's
    /// "upright" matches the phone's mounting angle. 0 = not yet
    /// calibrated, in which case the service emits confidence = 0
    /// and the firmware shows "Hold BOOT to calibrate".
    private var calibrationOffsetX10: Int16 = 0
    private var isCalibrated: Bool = false
    private var lastSnapshotX10: Int16 = 0

    public init(
        provider: any MotionProvider,
        smoothingAlpha: Double = LeanAngleCalculator.defaultSmoothingAlpha
    ) {
        self.provider = provider
        self.calculator = LeanAngleCalculator(smoothingAlpha: smoothingAlpha)
        self.encodedPayloads = channel.makeStream()
    }

    /// Capture the current lean angle as the new upright reference.
    /// Called by ``RideSession`` when the firmware long-press status
    /// arrives. After this returns, future emits are offset-adjusted
    /// and confidence becomes 100.
    public func calibrate() {
        lock.lock()
        calibrationOffsetX10 = lastSnapshotX10
        isCalibrated = true
        lock.unlock()
    }

    /// Start consuming samples from the provider. Idempotent: calling
    /// twice while a forwarding task is alive is a no-op.
    public func start() {
        guard forwardingTask == nil else { return }
        let stream = provider.samples
        forwardingTask = Task { [weak self] in
            for await sample in stream {
                guard let self else { return }
                if let data = self.encode(sample) {
                    self.channel.emit(data)
                }
            }
            self?.channel.finish()
        }
    }

    /// Stop forwarding and terminate ``encodedPayloads``.
    public func stop() {
        forwardingTask?.cancel()
        forwardingTask = nil
        channel.finish()
    }

    /// Reset the rolling lean state (current value and max-L / max-R).
    /// Useful between rides.
    public func reset() {
        lock.lock()
        calculator = calculator.reset()
        lock.unlock()
    }

    /// Pure transform from a single ``MotionSample`` to an encoded payload.
    /// Exposed for unit testing without spinning up the forwarding task.
    func encode(_ sample: MotionSample) -> Data? {
        lock.lock()
        calculator = calculator.ingesting(sample)
        var snapshot = calculator.snapshot
        lastSnapshotX10 = snapshot.currentLeanDegX10
        if isCalibrated {
            let raw = Int(snapshot.currentLeanDegX10) - Int(calibrationOffsetX10)
            snapshot.currentLeanDegX10 = Int16(max(-900, min(900, raw)))
            // Reset max accumulators to zero so they don't carry the
            // pre-cal noise.
            snapshot.confidencePercent = 100
        } else {
            // Force confidence=0 until the rider calibrates so the
            // firmware screen shows the calibrate prompt.
            snapshot.confidencePercent = 0
        }
        lock.unlock()
        do {
            return try ScreenPayloadCodec.encode(.leanAngle(snapshot, flags: []))
        } catch {
            return nil
        }
    }

    /// Read-only view of the current calculator state. Test-only.
    var currentCalculator: LeanAngleCalculator {
        lock.lock()
        defer { lock.unlock() }
        return calculator
    }
}
