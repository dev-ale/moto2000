import Foundation
import RideSimulatorKit

/// Real-device ``NowPlayingProvider`` that periodically polls an injected
/// ``NowPlayingClient`` on a ``SimulatedClock`` and republishes the results
/// as ``NowPlayingSnapshot`` values through an ``AsyncStream``.
///
/// Hermetic tests pass in a ``StaticNowPlayingClient`` + ``VirtualClock``;
/// production code eventually passes in ``MediaPlayerNowPlayingClient`` +
/// ``WallClock`` — though today the media-player client just throws
/// `.notImplemented`, see docs/platform-limits.md.
///
/// Errors during fetch are logged (via `NSLog`) and the polling loop
/// continues so a transient system hiccup doesn't kill the stream. When
/// the client returns `nil` (nothing is playing), no snapshot is emitted
/// for that tick — consumers see a pause in the stream, not a placeholder.
public final class RealNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    public static let defaultRefreshInterval: Double = 2.0

    private let client: any NowPlayingClient
    private let clock: any SimulatedClock
    private let refreshIntervalSeconds: Double
    private let startTime: Date
    private let channel = NowPlayingChannel()
    public let snapshots: AsyncStream<NowPlayingSnapshot>

    private let taskLock = NSLock()
    private var pollingTask: Task<Void, Never>?

    public init(
        client: any NowPlayingClient,
        clock: any SimulatedClock,
        refreshIntervalSeconds: Double = RealNowPlayingProvider.defaultRefreshInterval,
        startTime: Date = Date()
    ) {
        self.client = client
        self.clock = clock
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.startTime = startTime
        self.snapshots = channel.makeStream()
    }

    public func start() async {
        startSync()
    }

    public func stop() async {
        stopSync()
    }

    private func startSync() {
        taskLock.lock()
        defer { taskLock.unlock() }
        if pollingTask != nil { return }
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
            return
        }
    }

    private func stopSync() {
        taskLock.lock()
        let task = pollingTask
        pollingTask = nil
        taskLock.unlock()
        task?.cancel()
        channel.finish()
    }

    // MARK: - Polling loop

    private func runPollingLoop() async {
        var nextTime = await clock.nowSeconds
        while !Task.isCancelled {
            do {
                try await clock.sleep(until: nextTime)
            } catch {
                return
            }
            if Task.isCancelled {
                return
            }
            do {
                if let response = try await client.fetchNowPlaying() {
                    let scenarioTime = await clock.nowSeconds
                    let snapshot = NowPlayingSnapshot(
                        scenarioTime: scenarioTime,
                        title: response.title,
                        artist: response.artist,
                        album: response.album,
                        isPlaying: response.isPlaying,
                        positionSeconds: response.positionSeconds ?? -1.0,
                        durationSeconds: response.durationSeconds ?? -1.0
                    )
                    channel.emit(snapshot)
                }
            } catch {
                NSLog("RealNowPlayingProvider: fetch failed: \(error)")
            }
            nextTime += refreshIntervalSeconds
        }
    }
}

/// Single-producer broadcaster for ``NowPlayingSnapshot`` values, mirroring
/// the ``ProviderChannel`` pattern used by the RideSimulatorKit mocks.
final class NowPlayingChannel: @unchecked Sendable {
    private var continuation: AsyncStream<NowPlayingSnapshot>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<NowPlayingSnapshot> {
        AsyncStream<NowPlayingSnapshot>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: NowPlayingSnapshot) {
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
