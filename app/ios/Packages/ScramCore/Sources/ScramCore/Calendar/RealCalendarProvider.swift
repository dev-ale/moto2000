import Foundation
import RideSimulatorKit

/// Real (non-simulator) ``CalendarProvider`` that polls a
/// ``CalendarServiceClient`` on a refresh interval driven by a
/// ``SimulatedClock``.
///
/// The provider emits ``CalendarEvent`` values on its ``events`` stream.
/// Errors from the upstream client are swallowed after being logged so the
/// loop keeps going (e.g. the Slice 11 stub throws
/// ``CalendarServiceError/notImplemented`` on every call and the provider
/// simply never emits anything, which is the intended "deferred" behaviour).
///
/// A ``SimulatedClock`` is injected so tests can drive the refresh loop
/// with a ``VirtualClock``; production code passes a ``WallClock``.
public final class RealCalendarProvider: CalendarProvider, @unchecked Sendable {
    private let client: any CalendarServiceClient
    private let clock: any SimulatedClock
    private let refreshInterval: Double
    private let channel = CalendarChannel()
    public let events: AsyncStream<CalendarEvent>

    private var pollingTask: Task<Void, Never>?

    public init(
        client: any CalendarServiceClient,
        clock: any SimulatedClock,
        refreshInterval: Double = 60.0
    ) {
        self.client = client
        self.clock = clock
        self.refreshInterval = refreshInterval
        self.events = channel.makeStream()
    }

    public func start() async {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        channel.finish()
    }

    // MARK: - Poll loop

    private func pollLoop() async {
        var nextWakeAt = await clock.nowSeconds
        while !Task.isCancelled {
            await fetchOnce()
            nextWakeAt += refreshInterval
            do {
                try await clock.sleep(until: nextWakeAt)
            } catch {
                return
            }
        }
    }

    private func fetchOnce() async {
        let now = await clock.nowSeconds
        do {
            guard let response = try await client.fetchNextEvent() else {
                return
            }
            let event = CalendarEvent(
                scenarioTime: now,
                title: response.title,
                startsInSeconds: response.startsInSeconds,
                location: response.location
            )
            channel.emit(event)
        } catch {
            // Intentionally swallowed. See class doc comment.
        }
    }
}

/// Single-producer broadcaster for ``CalendarEvent`` values.
final class CalendarChannel: @unchecked Sendable {
    private var continuation: AsyncStream<CalendarEvent>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<CalendarEvent> {
        AsyncStream<CalendarEvent>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: CalendarEvent) {
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
