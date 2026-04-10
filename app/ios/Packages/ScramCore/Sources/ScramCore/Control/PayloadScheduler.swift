import Foundation
import BLEProtocol

/// Applies alert priority logic to outgoing screen payloads before they reach
/// the BLE transport.
///
/// Rules:
/// - **Incoming call** (``ScreenID/incomingCall``, priority 1) always overlays
///   immediately, replacing any active alert.
/// - **Blitzer** (``ScreenID/blitzer``, priority 2) during active navigation
///   does NOT overlay. Instead, the scheduler re-sends the cached navigation
///   payload with the ALERT flag (bit 0 of the flags byte) set.
/// - **Blitzer** when navigation is NOT active overlays normally.
/// - Only one alert overlay is active at a time; an incoming call replaces a
///   blitzer, but a blitzer cannot replace an incoming call.
///
/// The scheduler operates on raw `Data` blobs so it can be tested without
/// standing up the full BLE stack.
public final class PayloadScheduler: @unchecked Sendable {

    /// Index of the flags byte inside every screen payload header.
    private static let flagsOffset = 2

    /// Which alert screen is currently overlaying, if any.
    /// `nil` means no alert is active.
    public private(set) var activeAlert: ScreenID?

    /// The ScreenID of the most recently forwarded non-alert payload.
    public var activeScreen: ScreenID?

    /// Most recently seen navigation payload (raw Data), kept for ALERT-flag
    /// injection when a blitzer fires during navigation.
    private var cachedNavigationPayload: Data?

    public init() {}

    // MARK: - Public API

    /// Process an incoming encoded payload and return zero, one, or more
    /// payloads that should be written to the peripheral.
    ///
    /// The returned array is usually a single element but may be empty (e.g.
    /// a blitzer that is suppressed by an active incoming-call alert).
    public func schedule(_ payload: Data) -> [Data] {
        guard let screenID = Self.peekScreenID(payload) else {
            // Can't parse — forward as-is to avoid dropping data.
            return [payload]
        }
        let isAlert = Self.peekAlertFlag(payload)

        switch screenID {
        // ------------------------------------------------------------------
        // Incoming call — highest priority, always overlay
        // ------------------------------------------------------------------
        case .incomingCall:
            if isAlert {
                activeAlert = .incomingCall
            } else {
                // Call ended (ALERT flag cleared) — clear the alert.
                if activeAlert == .incomingCall {
                    activeAlert = nil
                }
            }
            return [payload]

        // ------------------------------------------------------------------
        // Blitzer — priority 2
        // ------------------------------------------------------------------
        case .blitzer:
            // A blitzer cannot replace an active incoming-call alert.
            if activeAlert == .incomingCall {
                return []
            }

            if isAlert {
                // If navigation is the active screen, inject ALERT into the
                // cached nav payload instead of sending the blitzer overlay.
                if activeScreen == .navigation, let navPayload = cachedNavigationPayload {
                    activeAlert = .blitzer
                    return [Self.setAlertFlag(on: navPayload)]
                }
                // Not navigating — send blitzer as a normal overlay.
                activeAlert = .blitzer
                return [payload]
            } else {
                // Blitzer clear payload (ALERT flag not set).
                if activeAlert == .blitzer {
                    activeAlert = nil
                }
                // If nav is active, re-send cached nav payload with ALERT cleared
                // so the ESP32 knows the alert is over.
                if activeScreen == .navigation, let navPayload = cachedNavigationPayload {
                    return [Self.clearAlertFlag(on: navPayload)]
                }
                return [payload]
            }

        // ------------------------------------------------------------------
        // Navigation — cache it for later ALERT-flag injection
        // ------------------------------------------------------------------
        case .navigation:
            cachedNavigationPayload = payload
            activeScreen = .navigation
            return [payload]

        // ------------------------------------------------------------------
        // Any other screen
        // ------------------------------------------------------------------
        default:
            if !isAlert {
                activeScreen = screenID
                // If we moved away from navigation, drop the cached payload.
                if screenID != .navigation {
                    cachedNavigationPayload = nil
                }
            }
            return [payload]
        }
    }

    /// Forcibly clear the active alert state (e.g. on ride end).
    public func clearAlert() {
        activeAlert = nil
    }

    // MARK: - Header helpers

    /// Read the ``ScreenID`` from byte 1 of a raw payload.
    static func peekScreenID(_ data: Data) -> ScreenID? {
        guard data.count > 1 else { return nil }
        return ScreenID(rawValue: data[data.startIndex + 1])
    }

    /// Returns `true` when the ALERT bit (bit 0 of the flags byte) is set.
    static func peekAlertFlag(_ data: Data) -> Bool {
        guard data.count > flagsOffset else { return false }
        return (data[data.startIndex + flagsOffset] & ScreenFlags.alert.rawValue) != 0
    }

    /// Return a copy of `data` with the ALERT bit set in the flags byte.
    static func setAlertFlag(on data: Data) -> Data {
        var copy = data
        guard copy.count > flagsOffset else { return copy }
        copy[copy.startIndex + flagsOffset] |= ScreenFlags.alert.rawValue
        return copy
    }

    /// Return a copy of `data` with the ALERT bit cleared in the flags byte.
    static func clearAlertFlag(on data: Data) -> Data {
        var copy = data
        guard copy.count > flagsOffset else { return copy }
        copy[copy.startIndex + flagsOffset] &= ~ScreenFlags.alert.rawValue
        return copy
    }
}
