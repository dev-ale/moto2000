import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``LocationSample`` values from any ``LocationProvider`` into
/// encoded BLE payloads for the `compass` screen, and exposes them as
/// an ``AsyncStream`` of `Data` blobs ready to write to the peripheral.
///
/// Transform rules:
///  - Heading: sourced from `CLLocation.course` (GPS course over ground).
///    Both `magneticHeadingDegX10` and `trueHeadingDegX10` are set to the
///    same GPS course value since we do not use `CLHeading`.
///  - Standstill hold: when speed < 3 km/h or course is negative (invalid),
///    the last known heading is retained.
///  - Accuracy: derived from GPS `horizontalAccuracyMeters`. Clamped to
///    the wire range `0..=3599` (i.e. 0.0..359.9 degrees).
///  - Flags: `useTrueHeading` is set because the GPS course represents a
///    true (geographic north) heading.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once.
public final class CompassService: PayloadService, @unchecked Sendable {
    private let provider: any LocationProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>

    /// PayloadService conformance — alias for encodedPayloads.
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    private var forwardingTask: Task<Void, Never>?
    private var lastHeadingDegX10: UInt16 = 0

    /// Speed threshold below which course is considered unreliable (3 km/h).
    private static let standstillSpeedMps: Double = 3.0 / 3.6

    public init(provider: any LocationProvider) {
        self.provider = provider
        self.encodedPayloads = channel.makeStream()
    }

    /// Start consuming samples from the underlying provider. Idempotent:
    /// calling twice has no effect while a forwarding task is alive.
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

    // MARK: - Transform

    func encode(_ sample: LocationSample) -> Data? {
        let headingDegX10: UInt16

        // Hold last heading when course is invalid or speed is below standstill threshold.
        let courseInvalid = sample.courseDegrees < 0
        let standstill = sample.speedMps < Self.standstillSpeedMps
        if courseInvalid || standstill {
            headingDegX10 = lastHeadingDegX10
        } else {
            let raw = Int((sample.courseDegrees * 10.0).rounded())
            let mod = ((raw % 3600) + 3600) % 3600
            headingDegX10 = UInt16(mod)
        }
        lastHeadingDegX10 = headingDegX10

        // Accuracy: convert horizontal accuracy in metres to a rough heading
        // accuracy in degrees x10. GPS horizontal accuracy doesn't map 1:1 to
        // heading accuracy, but it's the best proxy available without CLHeading.
        // Clamp to 0..3599.
        let accuracyDeg = max(0, min(359.9, sample.horizontalAccuracyMeters))
        let accuracyDegX10 = UInt16((accuracyDeg * 10.0).rounded())

        let compassData = CompassData(
            magneticHeadingDegX10: headingDegX10,
            trueHeadingDegX10: headingDegX10,
            headingAccuracyDegX10: accuracyDegX10,
            flags: CompassData.useTrueHeadingFlag
        )

        do {
            return try ScreenPayloadCodec.encode(.compass(compassData, flags: []))
        } catch {
            // Encoding should not fail after clamping; treat as drop.
            return nil
        }
    }
}
