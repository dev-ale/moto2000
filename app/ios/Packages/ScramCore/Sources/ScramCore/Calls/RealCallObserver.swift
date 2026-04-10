import Foundation
import RideSimulatorKit

/// Real-device implementation of ``CallObserver`` backed by a ``CallKitClient``.
///
/// On a real iPhone, the client would be a ``CXCallObserverClient`` that polls
/// `CXCallObserver`. For tests and the simulator, the client is
/// ``StaticCallKitClient`` or the scenario-driven mock.
///
/// This observer starts a polling loop when ``start()`` is called and emits
/// ``CallEvent`` values on the ``events`` stream whenever a new state is
/// detected. Polling frequency is 1s.
public final class RealCallObserver: CallObserver, @unchecked Sendable {
    private let client: any CallKitClient
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<CallEvent>.Continuation?

    public let events: AsyncStream<CallEvent>

    public init(client: any CallKitClient) {
        self.client = client
        var cont: AsyncStream<CallEvent>.Continuation?
        self.events = AsyncStream<CallEvent>(bufferingPolicy: .unbounded) { c in
            cont = c
        }
        self.continuation = cont
    }

    public func start() async {
        guard beginStart() else { return }
    }

    private nonisolated func beginStart() -> Bool {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            return false
        }
        task = Task { [weak self] in
            var lastState: CallKitClientResponse.State?
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    if let response = try await self.client.fetchCallState() {
                        if response.state != lastState {
                            lastState = response.state
                            let state: CallState
                            switch response.state {
                            case .incoming: state = .incoming
                            case .connected: state = .connected
                            case .ended: state = .ended
                            }
                            let event = CallEvent(
                                scenarioTime: 0,
                                state: state,
                                callerHandle: response.callerHandle
                            )
                            self.emitEvent(event)
                        }
                    } else {
                        lastState = nil
                    }
                } catch {
                    // Client not implemented or permission denied; stop polling.
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        lock.unlock()
        return true
    }

    private nonisolated func emitEvent(_ event: CallEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }

    public func stop() async {
        let (t, cont) = extractStopState()
        t?.cancel()
        cont?.finish()
    }

    private nonisolated func extractStopState() -> (Task<Void, Never>?, AsyncStream<CallEvent>.Continuation?) {
        lock.lock()
        let t = task
        task = nil
        let cont = continuation
        continuation = nil
        lock.unlock()
        return (t, cont)
    }
}
