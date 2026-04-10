import Foundation

/// Abstraction over `UIApplication` background-task APIs so unit tests
/// never import UIKit.
public protocol BackgroundTaskRunner: Sendable {
    /// Begin a background task. Returns a task identifier.
    func beginBackgroundTask(expirationHandler: (@Sendable () -> Void)?) -> Int
    /// End a previously started background task.
    func endBackgroundTask(_ identifier: Int)
}

/// Manages the lifecycle of a single ride, ensuring critical work (trip
/// summary save) completes even after the app enters the background.
///
/// `RideSession` does not own the location or motion providers — those
/// are started and stopped by the caller. Its sole responsibility is
/// requesting background execution time from the OS so a clean shutdown
/// can persist the trip summary before the process is suspended.
public final class RideSession: Sendable {
    /// Sentinel returned by ``BackgroundTaskRunner`` when no task is needed.
    public static let invalidTaskID: Int = 0

    private let runner: any BackgroundTaskRunner
    private let taskID: LockedBox<Int>

    public init(runner: any BackgroundTaskRunner) {
        self.runner = runner
        self.taskID = LockedBox(RideSession.invalidTaskID)
    }

    /// Call when the ride ends (e.g. BLE disconnect). Requests background
    /// execution time from the OS and invokes `save`. The closure must
    /// complete promptly (< 30 s). The background task is ended
    /// automatically once `save` returns or the OS forces expiration.
    public func finishRide(save: @Sendable () async -> Void) async {
        let id = runner.beginBackgroundTask { [weak self] in
            // Expiration handler: end the task if the OS is about to kill us.
            guard let self else { return }
            let current = self.taskID.value
            if current != RideSession.invalidTaskID {
                self.runner.endBackgroundTask(current)
                self.taskID.value = RideSession.invalidTaskID
            }
        }
        taskID.value = id

        await save()

        let current = taskID.value
        if current != RideSession.invalidTaskID {
            runner.endBackgroundTask(current)
            taskID.value = RideSession.invalidTaskID
        }
    }
}

// MARK: - Thread-safe box

/// A trivial lock-protected mutable value used by ``RideSession`` to
/// share the background-task identifier between the async save path and
/// the synchronous expiration handler.
final class LockedBox<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
