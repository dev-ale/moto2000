import BLEProtocol
import Foundation

/// Manages OTA firmware update operations from the iOS side.
///
/// The service holds the current firmware version (reported by the ESP32
/// at connection time) and can trigger an OTA check by emitting a
/// ``ControlCommand/checkForOTAUpdate`` over the control channel.
///
/// The actual HTTP download and flash happen on the ESP32 side — this
/// service only initiates the check and observes progress.
public actor OTAService {
    /// The firmware version currently running on the connected ESP32.
    public private(set) var currentVersion: FirmwareVersion?

    /// Stream of control commands to send to the ESP32.
    public nonisolated let commands: AsyncStream<ControlCommand>
    private let continuation: AsyncStream<ControlCommand>.Continuation

    public init() {
        var cont: AsyncStream<ControlCommand>.Continuation!
        self.commands = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    deinit {
        continuation.finish()
    }

    /// Update the locally cached firmware version (called when the ESP32
    /// reports its version at connection time).
    public func setCurrentVersion(_ version: FirmwareVersion) {
        self.currentVersion = version
    }

    /// Request the ESP32 to check for a firmware update.
    ///
    /// This emits a ``ControlCommand/checkForOTAUpdate`` command. The ESP32
    /// will compare its version against the latest available release and
    /// begin downloading if newer.
    public func checkForUpdate() {
        continuation.yield(.checkForOTAUpdate)
    }

    /// Used by tests to drain the stream once the producer is done.
    public func finish() {
        continuation.finish()
    }
}
