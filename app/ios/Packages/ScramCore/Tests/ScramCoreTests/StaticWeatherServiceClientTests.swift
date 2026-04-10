import XCTest
import RideSimulatorKit

@testable import ScramCore

final class StaticWeatherServiceClientTests: XCTestCase {
    func test_fetchCurrentWeather_returnsScriptedResponse() async throws {
        let expected = WeatherServiceResponse(
            condition: .cloudy,
            temperatureCelsius: 14.0,
            highCelsius: 17.0,
            lowCelsius: 9.0,
            locationName: "Basel"
        )
        let client = StaticWeatherServiceClient(response: expected)

        let got = try await client.fetchCurrentWeather(latitude: 47.5, longitude: 7.6)
        XCTAssertEqual(got, expected)
        XCTAssertEqual(client.callCount, 1)
    }

    func test_setResponse_swapsUpstream() async throws {
        let initial = WeatherServiceResponse(
            condition: .clear,
            temperatureCelsius: 20,
            highCelsius: 22,
            lowCelsius: 15,
            locationName: "Basel"
        )
        let client = StaticWeatherServiceClient(response: initial)

        _ = try await client.fetchCurrentWeather(latitude: 0, longitude: 0)

        let updated = WeatherServiceResponse(
            condition: .rain,
            temperatureCelsius: 12,
            highCelsius: 18,
            lowCelsius: 10,
            locationName: "Basel"
        )
        client.setResponse(updated)

        let got = try await client.fetchCurrentWeather(latitude: 0, longitude: 0)
        XCTAssertEqual(got, updated)
        XCTAssertEqual(client.callCount, 2)
    }
}
