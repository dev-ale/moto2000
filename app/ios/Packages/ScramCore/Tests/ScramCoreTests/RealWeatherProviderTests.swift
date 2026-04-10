import XCTest
import RideSimulatorKit

@testable import ScramCore

final class RealWeatherProviderTests: XCTestCase {
    private func basel() -> RealWeatherProvider.Coordinate {
        .init(latitude: 47.5596, longitude: 7.5886)
    }

    func test_start_emitsInitialSnapshot() async throws {
        let response = WeatherServiceResponse(
            condition: .clear,
            temperatureCelsius: 22.5,
            highCelsius: 25.0,
            lowCelsius: 13.0,
            locationName: "Basel"
        )
        let client = StaticWeatherServiceClient(response: response)
        let clock = VirtualClock()
        let provider = RealWeatherProvider(
            client: client,
            clock: clock,
            coordinate: basel(),
            refreshInterval: 60.0
        )

        let stream = provider.snapshots
        var iterator = stream.makeAsyncIterator()

        await provider.start()

        let firstOptional = await iterator.next()
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.condition, .clear)
        XCTAssertEqual(first.temperatureCelsius, 22.5, accuracy: 1e-9)
        XCTAssertEqual(first.highCelsius, 25.0, accuracy: 1e-9)
        XCTAssertEqual(first.lowCelsius, 13.0, accuracy: 1e-9)
        XCTAssertEqual(first.locationName, "Basel")
        XCTAssertEqual(first.scenarioTime, 0, accuracy: 1e-9)

        await provider.stop()
    }

    func test_pollLoop_fetchesOnRefreshInterval() async throws {
        let response = WeatherServiceResponse(
            condition: .cloudy,
            temperatureCelsius: 15.0,
            highCelsius: 18.0,
            lowCelsius: 10.0,
            locationName: "Basel"
        )
        let client = StaticWeatherServiceClient(response: response)
        let clock = VirtualClock()
        let provider = RealWeatherProvider(
            client: client,
            clock: clock,
            coordinate: basel(),
            refreshInterval: 60.0
        )

        let stream = provider.snapshots
        var iterator = stream.makeAsyncIterator()
        await provider.start()

        // Initial snapshot at t=0.
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

        XCTAssertGreaterThanOrEqual(client.callCount, 3)
        await provider.stop()
    }

    func test_stop_terminatesStream() async {
        let response = WeatherServiceResponse(
            condition: .clear,
            temperatureCelsius: 20,
            highCelsius: 22,
            lowCelsius: 15,
            locationName: "Basel"
        )
        let client = StaticWeatherServiceClient(response: response)
        let clock = VirtualClock()
        let provider = RealWeatherProvider(
            client: client,
            clock: clock,
            coordinate: basel(),
            refreshInterval: 60.0
        )
        let stream = provider.snapshots
        await provider.start()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next() // drain initial
        await provider.stop()

        let next = await iterator.next()
        XCTAssertNil(next, "stream should terminate after stop()")
    }
}
