import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class CalendarServiceTests: XCTestCase {
    func test_encode_producesValidPayload() throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        let event = CalendarEvent(
            scenarioTime: 0,
            title: "Coffee at Kaffee Lade",
            startsInSeconds: 1800.0,
            location: "Basel"
        )
        let blob = try XCTUnwrap(service.encode(event))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.startsInMinutes, 30)
        XCTAssertEqual(data.title, "Coffee at Kaffee Lade")
        XCTAssertEqual(data.location, "Basel")
    }

    func test_encode_nowEvent() throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        let event = CalendarEvent(
            scenarioTime: 0, title: "Team standup",
            startsInSeconds: 0, location: "Room A"
        )
        let blob = try XCTUnwrap(service.encode(event))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.startsInMinutes, 0)
    }

    func test_encode_pastEvent() throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        let event = CalendarEvent(
            scenarioTime: 0, title: "Lunch",
            startsInSeconds: -900, location: "Here"
        )
        let blob = try XCTUnwrap(service.encode(event))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.startsInMinutes, -15)
    }

    func test_secondsToMinutesClamped_rounding() {
        // 90 seconds = 1.5 minutes → rounds toward zero → 1
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(90), 1)
        // -90 seconds = -1.5 minutes → rounds toward zero → -1
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(-90), -1)
        // Exact
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(1800), 30)
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(0), 0)
    }

    func test_secondsToMinutesClamped_clamping() {
        // Beyond max: 10081 minutes in seconds
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(10081 * 60), 10080)
        // Beyond min: -1441 minutes in seconds
        XCTAssertEqual(CalendarService.secondsToMinutesClamped(-1441 * 60), -1440)
    }

    func test_encode_truncatesLongTitle() throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        let longTitle = String(repeating: "A", count: 64)
        let event = CalendarEvent(
            scenarioTime: 0, title: longTitle,
            startsInSeconds: 600, location: "ok"
        )
        let blob = try XCTUnwrap(service.encode(event))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.title.utf8.count, 31)
    }

    func test_encode_truncatesLongLocation() throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        let longLocation = String(repeating: "B", count: 48)
        let event = CalendarEvent(
            scenarioTime: 0, title: "ok",
            startsInSeconds: 600, location: longLocation
        )
        let blob = try XCTUnwrap(service.encode(event))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.location.utf8.count, 23)
    }

    func test_start_forwardsEventsFromProvider() async throws {
        let provider = MockCalendarProvider()
        let service = CalendarService(provider: provider)

        service.start()

        let stream = service.encodedPayloads
        var iterator = stream.makeAsyncIterator()

        provider.emit(CalendarEvent(
            scenarioTime: 0,
            title: "Test event",
            startsInSeconds: 300,
            location: "Test location"
        ))

        let blobOptional = await iterator.next()
        let blob = try XCTUnwrap(blobOptional)
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .appointment(let data, _) = decoded else {
            XCTFail("expected appointment payload")
            return
        }
        XCTAssertEqual(data.startsInMinutes, 5)
        XCTAssertEqual(data.title, "Test event")
        XCTAssertEqual(data.location, "Test location")

        service.stop()
    }
}
