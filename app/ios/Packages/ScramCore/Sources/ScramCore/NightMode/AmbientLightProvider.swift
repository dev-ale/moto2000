import Foundation

/// A single ambient light measurement.
public struct AmbientLightSample: Sendable, Equatable {
    /// Illuminance in lux.
    public var lux: Double
    /// When the measurement was taken.
    public var timestamp: Date

    public init(lux: Double, timestamp: Date) {
        self.lux = lux
        self.timestamp = timestamp
    }
}

/// Abstracts the ambient light sensor so the brightness policy never
/// touches hardware directly.
///
/// Implementations:
/// - ``MockAmbientLightProvider``: test-only, emits scripted samples.
/// - ``SystemAmbientLightProvider``: stub on iOS (see doc comment there).
public protocol AmbientLightProvider: Sendable {
    /// Async stream of light samples. Multiple awaiters each get their
    /// own copy.
    var samples: AsyncStream<AmbientLightSample> { get }

    /// Start delivering samples. Idempotent.
    func start() async

    /// Stop delivering samples. Idempotent.
    func stop() async
}

// MARK: - MockAmbientLightProvider

/// Test-only ambient light provider that emits scripted samples.
public final class MockAmbientLightProvider: AmbientLightProvider, @unchecked Sendable {
    private let channel = LightChannel()
    public let samples: AsyncStream<AmbientLightSample>

    public init() {
        self.samples = channel.makeStream()
    }

    public func start() async {}

    public func stop() async {
        channel.finish()
    }

    /// Emit a sample into the stream. Used by tests.
    public func emit(_ sample: AmbientLightSample) {
        channel.emit(sample)
    }
}

/// Single-producer broadcaster for ambient light samples.
private final class LightChannel: @unchecked Sendable {
    private var continuation: AsyncStream<AmbientLightSample>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<AmbientLightSample> {
        AsyncStream<AmbientLightSample>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: AmbientLightSample) {
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

// MARK: - SystemAmbientLightProvider

/// Stub ambient light provider for iOS.
///
/// iOS does not expose a public ambient light sensor API. Real
/// implementation options for future slices:
///
/// 1. **Screen brightness as proxy** — read `UIScreen.main.brightness`
///    which iOS adjusts based on ambient light when auto-brightness is on.
///    Imprecise but zero-permission.
/// 2. **Camera-based lux estimation** — use AVCaptureDevice exposure
///    metadata to estimate ambient lux. Requires camera permission and
///    drains battery.
/// 3. **External BLE lux sensor** — a small BLE peripheral with a
///    TSL2591 or similar. Most accurate but requires extra hardware.
///
/// All are follow-ups. This stub emits nothing so the brightness policy
/// falls back to time-based decisions.
#if os(iOS)
public final class SystemAmbientLightProvider: AmbientLightProvider, @unchecked Sendable {
    public let samples: AsyncStream<AmbientLightSample>

    public init() {
        self.samples = AsyncStream { $0.finish() }
    }

    public func start() async {
        // No-op: no public iOS API for raw ambient light.
    }

    public func stop() async {
        // No-op.
    }
}
#endif
