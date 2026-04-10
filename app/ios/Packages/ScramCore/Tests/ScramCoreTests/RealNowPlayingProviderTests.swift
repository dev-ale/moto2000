import XCTest
import RideSimulatorKit

@testable import ScramCore

final class RealNowPlayingProviderTests: XCTestCase {
    func test_pollsAtRequestedInterval() async throws {
        let response = NowPlayingClientResponse(
            title: "Moving On",
            artist: "The Riders",
            album: "Asphalt",
            isPlaying: true,
            positionSeconds: 45,
            durationSeconds: 240
        )
        let client = StaticNowPlayingClient(response: response)
        let clock = VirtualClock()
        let provider = RealNowPlayingProvider(
            client: client,
            clock: clock,
            refreshIntervalSeconds: 2.0
        )

        var iterator = provider.snapshots.makeAsyncIterator()
        await provider.start()

        // Initial poll at t=0 should emit immediately.
        await clock.advance(to: 0)
        let first = await iterator.next()
        XCTAssertEqual(first?.title, "Moving On")
        XCTAssertEqual(first?.scenarioTime ?? -1, 0, accuracy: 1e-6)

        // Second poll at t=2.
        await clock.advance(to: 2)
        let second = await iterator.next()
        XCTAssertEqual(second?.title, "Moving On")
        XCTAssertEqual(second?.scenarioTime ?? -1, 2, accuracy: 1e-6)

        // Third poll at t=4.
        await clock.advance(to: 4)
        let third = await iterator.next()
        XCTAssertEqual(third?.scenarioTime ?? -1, 4, accuracy: 1e-6)

        await provider.stop()
    }

    func test_nilResponseEmitsNoSnapshot() async throws {
        let client = StaticNowPlayingClient(response: nil)
        let clock = VirtualClock()
        let provider = RealNowPlayingProvider(
            client: client,
            clock: clock,
            refreshIntervalSeconds: 1.0
        )
        await provider.start()

        // Drive several ticks; nothing should ever land on the stream.
        await clock.advance(to: 0)
        await clock.advance(to: 1)
        await clock.advance(to: 2)

        // Set a real response and advance again — the first emission should
        // be the one we just scripted.
        client.set(
            NowPlayingClientResponse(
                title: "Late Start",
                artist: "Band",
                album: "Album",
                isPlaying: true,
                positionSeconds: 0,
                durationSeconds: 60
            )
        )
        await clock.advance(to: 3)

        var iterator = provider.snapshots.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.title, "Late Start")

        await provider.stop()
    }

    func test_startIsIdempotent() async {
        let client = StaticNowPlayingClient()
        let clock = VirtualClock()
        let provider = RealNowPlayingProvider(client: client, clock: clock)
        await provider.start()
        await provider.start()
        await provider.stop()
    }
}
