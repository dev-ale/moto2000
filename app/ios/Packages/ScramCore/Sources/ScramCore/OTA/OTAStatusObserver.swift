import Foundation

/// The OTA progress state as reported by the ESP32 over the BLE `status`
/// characteristic.
///
/// This mirrors the C-side `ota_state_t` enum. The protocol boundary is
/// defined here so the iOS side can react to OTA progress without knowing
/// the transport details.
public enum OTAStatus: Equatable, Sendable {
    case idle
    case checking
    case downloading(progress: Double) // 0.0 ... 1.0
    case verifying
    case applying
    case rebooting
    case error(String)
}

/// Protocol for observing OTA status updates from the ESP32.
///
/// The real implementation will parse the `status` BLE characteristic
/// notifications. For now this is a protocol boundary — the concrete
/// implementation is deferred to hardware bring-up.
public protocol OTAStatusObserver: Sendable {
    /// An asynchronous stream of OTA status updates.
    var statusUpdates: AsyncStream<OTAStatus> { get }
}
