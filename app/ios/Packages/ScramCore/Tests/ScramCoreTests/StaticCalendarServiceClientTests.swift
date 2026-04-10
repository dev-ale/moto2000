import XCTest
import RideSimulatorKit

@testable import ScramCore

final class StaticCalendarServiceClientTests: XCTestCase {
    func test_returnsScriptedResponse() async throws {
        let response = CalendarServiceResponse(
            title: "Coffee at Kaffee Lade",
            startsInSeconds: 1800.0,
            location: "Basel"
        )
        let client = StaticCalendarServiceClient(response: response)
        let result = try await client.fetchNextEvent()
        XCTAssertEqual(result, response)
        XCTAssertEqual(client.callCount, 1)
    }

    func test_returnsNilWhenNoResponse() async throws {
        let client = StaticCalendarServiceClient()
        let result = try await client.fetchNextEvent()
        XCTAssertNil(result)
        XCTAssertEqual(client.callCount, 1)
    }

    func test_swappingResponseAtRuntime() async throws {
        let client = StaticCalendarServiceClient(response: CalendarServiceResponse(
            title: "Meeting A",
            startsInSeconds: 600,
            location: "Room 1"
        ))
        let first = try await client.fetchNextEvent()
        XCTAssertEqual(first?.title, "Meeting A")

        client.setResponse(CalendarServiceResponse(
            title: "Meeting B",
            startsInSeconds: 1200,
            location: "Room 2"
        ))
        let second = try await client.fetchNextEvent()
        XCTAssertEqual(second?.title, "Meeting B")
        XCTAssertEqual(client.callCount, 2)
    }
}
