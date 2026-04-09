import Foundation

/// Abstraction over "how does time advance in the simulator".
///
/// The scenario player never reads `Date()` directly. Instead it awaits a
/// clock to sleep until a specific scenario timestamp, then asks for
/// `now`. Tests inject a ``VirtualClock`` that advances instantly and
/// deterministically; the dev-build UI injects a ``WallClock`` that
/// actually sleeps.
public protocol SimulatedClock: Sendable {
    /// Current time inside the simulation, in seconds since the scenario
    /// started.
    var nowSeconds: Double { get async }

    /// Suspends until the simulation reaches `scenarioSeconds`.
    func sleep(until scenarioSeconds: Double) async throws
}

/// A clock that advances by calling real `Task.sleep`.
///
/// The wall clock applies a `speedMultiplier` so "1 scenario second" can
/// mean 0.1 real seconds at 10× replay speed. Negative or zero multipliers
/// are rejected.
public actor WallClock: SimulatedClock {
    public struct InvalidSpeed: Error, Equatable, Sendable {
        public let speed: Double
    }

    private let startRealTime: ContinuousClock.Instant
    private let speedMultiplier: Double

    public init(speedMultiplier: Double = 1.0) throws {
        guard speedMultiplier > 0 else {
            throw InvalidSpeed(speed: speedMultiplier)
        }
        self.startRealTime = ContinuousClock.now
        self.speedMultiplier = speedMultiplier
    }

    public var nowSeconds: Double {
        let elapsed = ContinuousClock.now - startRealTime
        return elapsed.seconds * speedMultiplier
    }

    public func sleep(until scenarioSeconds: Double) async throws {
        let current = nowSeconds
        guard scenarioSeconds > current else { return }
        let realSecondsToSleep = (scenarioSeconds - current) / speedMultiplier
        let nanos = UInt64(realSecondsToSleep * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}

/// A clock that advances only when tests tell it to. Perfect for
/// deterministic unit tests of the scenario player.
///
/// `sleep(until:)` records the requested wake time and suspends until the
/// test calls ``advance(to:)`` past that mark. Multiple concurrent sleepers
/// are supported and wake in timestamp order.
public actor VirtualClock: SimulatedClock {
    private var current: Double = 0
    private var waiters: [Waiter] = []

    private struct Waiter {
        let wakeAt: Double
        let continuation: CheckedContinuation<Void, Never>
    }

    public init(startingAt start: Double = 0) {
        self.current = start
    }

    public var nowSeconds: Double { current }

    public func sleep(until scenarioSeconds: Double) async throws {
        if scenarioSeconds <= current { return }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(wakeAt: scenarioSeconds, continuation: continuation))
            waiters.sort { $0.wakeAt < $1.wakeAt }
        }
    }

    /// Advances the virtual clock to `target`. Any sleeper whose wake-at is
    /// `<= target` is resumed in timestamp order before this call returns.
    public func advance(to target: Double) {
        guard target >= current else { return }
        current = target
        while let first = waiters.first, first.wakeAt <= current {
            waiters.removeFirst()
            first.continuation.resume()
        }
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
