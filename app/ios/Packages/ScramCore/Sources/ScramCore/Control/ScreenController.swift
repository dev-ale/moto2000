import Foundation
import BLEProtocol

/// Errors raised by the screen controller when a caller passes an
/// out-of-range value.
public enum ScreenControllerError: Error, Equatable, Sendable {
    case brightnessOutOfRange(UInt8)
}

/// Owns the iOS-side notion of "what screen should the panel show right now"
/// and translates user actions into encoded ``ControlCommand`` writes.
///
/// The controller does not know about CoreBluetooth — instead it exposes an
/// `AsyncStream<ControlCommand>` that the BLE transport drains. Tests
/// consume the same stream directly.
public actor ScreenController {
    public private(set) var activeScreen: ScreenID
    public nonisolated let commands: AsyncStream<ControlCommand>
    private let continuation: AsyncStream<ControlCommand>.Continuation

    public init(initialScreen: ScreenID = .clock) {
        self.activeScreen = initialScreen
        var cont: AsyncStream<ControlCommand>.Continuation!
        self.commands = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    deinit {
        continuation.finish()
    }

    public func setActiveScreen(_ id: ScreenID) {
        activeScreen = id
        continuation.yield(.setActiveScreen(id))
    }

    public func setBrightness(_ percent: UInt8) throws {
        guard percent <= 100 else {
            throw ScreenControllerError.brightnessOutOfRange(percent)
        }
        continuation.yield(.setBrightness(percent))
    }

    public func sleep() {
        continuation.yield(.sleep)
    }

    public func wake() {
        continuation.yield(.wake)
    }

    public func clearAlertOverlay() {
        continuation.yield(.clearAlertOverlay)
    }

    /// Used by tests to drain the stream once the producer is done.
    public func finish() {
        continuation.finish()
    }
}
