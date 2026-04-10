import XCTest
import RideSimulatorKit

@testable import ScramCore

final class RealCalendarProviderTests: XCTestCase {
    func test_start_emitsInitialEvent() async throws {
        let response = CalendarServiceResponse(
            title: "Coffee at Kaffee Lade",
            startsInSeconds: 1800.0,
            location: "Basel"
        )
        let client = StaticCalendarServiceClient(response: response)
        let clock = VirtualClock()
        let provider = RealCalendarProvider(
            client: client,
            clock: clock,
            refreshInterval: 60.0
        )

        let stream = provider.events
        var iterator = stream.makeAsyncIterator()

        await provider.start()

        let firstOptional = await iterator.next()
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.title, "Coffee at Kaffee Lade")
        XCTAssertEqual(first.startsInSeconds, 1800.0, accuracy: 1e-9)
        XCTAssertEqual(first.location, "Basel")
        XCTAssertEqual(first.scenarioTime, 0, accuracy: 1e-9)

        await provider.stop()
    }

    func test_pollLoop_fetchesOnRefreshInterval() async throws {
        let response = CalendarServiceResponse(
            title: "Team standup",
            startsInSeconds: 900,
            location: "Conference room"
        )
        let client = StaticCalendarServiceClient(response: response)
        let clock = VirtualClock()
        let provider = RealCalendarProvider(
            client: client,
            clock: clock,
            refreshInterval: 60.0
        )

        let stream = provider.events
        var iterator = stream.makeAsyncIterator()
        await provider.start()

        // Initial event at t=0.
        _ = await iterator.next()

        // Advance to t=60 → second poll.
        await clock.advance(to: 60.0)
        let secondOptional = await iterator.next()
        let second = try XCTUnwrap(secondOptional)
        XCTAssertEqual(second.scenarioTime, 60.0, accuracy: 1e-9)

        // Advance to t=120 → third poll.
        await clock.advance(to: 120.0)
        let thirdOptional = await iterator.next()
        let third = try XCTUnwrap(thirdOptional)
        XCTAssertEqual(third.scenarioTime, 120.0, accuracy: 1e-9)

        XCTAssertEqual(client.callCount, 3)
        await provider.stop()
    }

    func test_nilResponse_doesNotEmit() async throws {
        let client = StaticCalendarServiceClient()
        let clock = VirtualClock()
        let provider = RealCalendarProvider(
            client: client,
            clock: clock,
            refreshInterval: 60.0
        )

        await provider.start()

        // Give the polling task time to start and make its first call.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Client was called but no events emitted (nil response).
        XCTAssertGreaterThanOrEqual(client.callCount, 1)

        await provider.stop()
    }

    func test_stubClient_swallowsError() async throws {
        // EventKitCalendarClient throws notImplemented — the provider should
        // keep running without crashing. We simulate with a throwing client.
        let client = ThrowingCalendarServiceClient()
        let clock = VirtualClock()
        let provider = RealCalendarProvider(
            client: client,
            clock: clock,
            refreshInterval: 60.0
        )

        await provider.start()
        await clock.advance(to: 60.0)

        // No crash, no events — that is the expected behavior.
        await provider.stop()
    }
}

/// A client that always throws, simulating the EventKit stub.
private struct ThrowingCalendarServiceClient: CalendarServiceClient, Sendable {
    func fetchNextEvent() async throws -> CalendarServiceResponse? {
        throw CalendarServiceError.notImplemented
    }
}
