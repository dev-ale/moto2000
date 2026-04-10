import XCTest
import BLEProtocol

@testable import ScramCore

/// A mock ``ClockProvider`` that returns a fixed date, timezone, and
/// 24-hour preference. All properties are mutable so individual tests
/// can override them.
struct MockClockProvider: ClockProvider, Sendable {
    var fixedDate: Date
    var fixedTimeZone: TimeZone
    var fixedIs24Hour: Bool

    init(
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        timeZone: TimeZone = TimeZone(secondsFromGMT: 3600)!,
        is24Hour: Bool = true
    ) {
        self.fixedDate = date
        self.fixedTimeZone = timeZone
        self.fixedIs24Hour = is24Hour
    }

    func now() -> Date { fixedDate }
    func timeZone() -> TimeZone { fixedTimeZone }
    func is24Hour() -> Bool { fixedIs24Hour }
}

final class ClockServiceTests: XCTestCase {

    // MARK: - Encoding

    func test_encodeTick_producesValidClockPayload() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let tz = TimeZone(secondsFromGMT: 3600)!
        let provider = MockClockProvider(date: date, timeZone: tz, is24Hour: true)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertEqual(clock.unixTime, 1_700_000_000)
        XCTAssertEqual(clock.tzOffsetMinutes, 60)
        XCTAssertTrue(clock.is24Hour)
    }

    func test_encodeTick_12HourFlag() throws {
        let provider = MockClockProvider(is24Hour: false)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertFalse(clock.is24Hour)
    }

    func test_encodeTick_24HourFlag() throws {
        let provider = MockClockProvider(is24Hour: true)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertTrue(clock.is24Hour)
    }

    func test_encodeTick_negativeTimezoneOffset() throws {
        // UTC-5 = -18000 seconds
        let tz = TimeZone(secondsFromGMT: -18000)!
        let provider = MockClockProvider(timeZone: tz)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertEqual(clock.tzOffsetMinutes, -300)
    }

    func test_encodeTick_halfHourTimezoneOffset() throws {
        // IST = UTC+5:30 = 19800 seconds
        let tz = TimeZone(secondsFromGMT: 19800)!
        let provider = MockClockProvider(timeZone: tz)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertEqual(clock.tzOffsetMinutes, 330)
    }

    func test_encodeTick_roundTripsCorrectly() throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let tz = TimeZone(secondsFromGMT: -25200)! // UTC-7
        let provider = MockClockProvider(date: date, timeZone: tz, is24Hour: false)
        let service = ClockService(provider: provider)

        let blob = try XCTUnwrap(service.encodeTick())
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertEqual(clock.unixTime, 1_600_000_000)
        XCTAssertEqual(clock.tzOffsetMinutes, -420)
        XCTAssertFalse(clock.is24Hour)
    }

    // MARK: - Stream integration

    func test_start_emitsImmediately() async throws {
        let provider = MockClockProvider()
        let service = ClockService(provider: provider, tickInterval: 60)

        service.start()

        var iterator = service.encodedPayloads.makeAsyncIterator()
        let blobOptional = await iterator.next()
        let blob = try XCTUnwrap(blobOptional)
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .clock(let clock, _) = payload else {
            XCTFail("expected clock payload, got \(payload)")
            return
        }
        XCTAssertEqual(clock.unixTime, 1_700_000_000)

        service.stop()
    }

    func test_stop_terminatesStream() async throws {
        let provider = MockClockProvider()
        let service = ClockService(provider: provider, tickInterval: 60)

        service.start()

        var iterator = service.encodedPayloads.makeAsyncIterator()
        // Consume the immediate tick
        _ = await iterator.next()

        service.stop()

        // After stop, the stream should terminate (return nil).
        let afterStop = await iterator.next()
        XCTAssertNil(afterStop)
    }
}
