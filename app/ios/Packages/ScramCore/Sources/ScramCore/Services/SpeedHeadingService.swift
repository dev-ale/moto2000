import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``LocationSample`` values from any ``LocationProvider`` into
/// encoded BLE payloads for the `speedHeading` screen, and exposes them as
/// an ``AsyncStream`` of `Data` blobs ready to write to the peripheral.
///
/// Transform rules:
///  - Speed: negative `speedMps` (CoreLocation's "unknown" sentinel) is
///    clamped to 0. Otherwise we convert to km/h, multiply by 10, round,
///    and clamp to 3000 (30.0 km/h max is the wire limit).
///  - Heading: negative `courseDegrees` (CoreLocation's "unknown"
///    sentinel) reuses the previous heading, starting at 0 before the
///    first known heading. Otherwise `degrees * 10`, rounded and modded
///    by 3600 to fit the valid range.
///  - Altitude: rounded metres, clamped to the wire `Int16(-500..=9000)`
///    band via `Int16(clamping:)`.
///  - Temperature: hard-coded to 0 — there is no thermal provider yet.
///    Replace this when a dedicated slice ships one.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. It does not retain the provider's stream
/// iterator across starts.
public final class SpeedHeadingService: PayloadService, @unchecked Sendable {
    private let provider: any LocationProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    private var forwardingTask: Task<Void, Never>?
    private var lastHeadingDegX10: UInt16 = 0
    private var smoothedSpeedKmh: Double?

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
        let speedKmhX10: UInt16
        if sample.speedMps < 0 {
            // CoreLocation has no valid speed yet — keep the last
            // smoothed value rather than snapping to 0.
            let kmh = smoothedSpeedKmh ?? 0
            speedKmhX10 = UInt16(min(max((kmh * 10.0).rounded(), 0), 3000))
        } else {
            let rawKmh = sample.speedMps * 3.6
            // Light exponential moving average (alpha = 0.5) to absorb
            // GPS jitter without lagging real acceleration noticeably.
            let alpha = 0.5
            let smoothed = (smoothedSpeedKmh.map { $0 * (1 - alpha) + rawKmh * alpha }) ?? rawKmh
            smoothedSpeedKmh = smoothed
            let scaled = (smoothed * 10.0).rounded()
            speedKmhX10 = UInt16(min(max(scaled, 0), 3000))
        }

        let headingDegX10: UInt16
        if sample.courseDegrees < 0 {
            headingDegX10 = lastHeadingDegX10
        } else {
            let raw = Int((sample.courseDegrees * 10.0).rounded())
            let mod = ((raw % 3600) + 3600) % 3600
            headingDegX10 = UInt16(mod)
        }
        lastHeadingDegX10 = headingDegX10

        let altRounded = Int(sample.altitudeMeters.rounded())
        let altClamped = max(-500, min(9000, altRounded))
        let altitudeMeters = Int16(altClamped)

        // Temperature: no provider yet — see doc comment above.
        let temperatureCelsiusX10: Int16 = 0

        let data = SpeedHeadingData(
            speedKmhX10: speedKmhX10,
            headingDegX10: headingDegX10,
            altitudeMeters: altitudeMeters,
            temperatureCelsiusX10: temperatureCelsiusX10
        )
        do {
            return try ScreenPayloadCodec.encode(.speedHeading(data, flags: []))
        } catch {
            // Encoding should not fail after clamping; treat as drop.
            return nil
        }
    }
}
