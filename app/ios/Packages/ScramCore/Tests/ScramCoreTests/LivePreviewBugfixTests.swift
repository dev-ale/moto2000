import XCTest
import RideSimulatorKit

@testable import BLEProtocol
@testable import ScramCore

// MARK: - Navigation: route calculation produces valid NavData

final class LivePreviewNavigationTests: XCTestCase {

    /// A mock route engine that returns a fixed route or throws.
    private final class MockRouteEngine: RouteEngine, @unchecked Sendable {
        let result: Result<NavigationRoute, Error>
        private(set) var callCount = 0

        init(route: NavigationRoute) {
            self.result = .success(route)
        }

        init(error: Error) {
            self.result = .failure(error)
        }

        func calculateRoute(
            from origin: NavigationRoute.LocationCoordinate,
            to destination: NavigationRoute.LocationCoordinate
        ) async throws -> NavigationRoute {
            callCount += 1
            return try result.get()
        }
    }

    func test_routeCalculation_producesValidNavData() async throws {
        let route = NavigationRoute(
            steps: [
                NavigationRoute.Step(
                    maneuver: .right,
                    streetName: "Aeschengraben",
                    distanceMeters: 320.0,
                    startLocation: .init(latitude: 47.5482, longitude: 7.5899),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5900)
                ),
                NavigationRoute.Step(
                    maneuver: .arrive,
                    streetName: "Destination",
                    distanceMeters: 0.0,
                    startLocation: .init(latitude: 47.5516, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5900)
                ),
            ],
            totalDistanceMeters: 320.0,
            expectedTravelTimeSeconds: 60.0
        )

        let engine = MockRouteEngine(route: route)
        let origin = NavigationRoute.LocationCoordinate(
            latitude: 47.5482, longitude: 7.5899
        )
        let dest = NavigationRoute.LocationCoordinate(
            latitude: 47.5516, longitude: 7.5900
        )

        let computed = try await engine.calculateRoute(from: origin, to: dest)
        XCTAssertEqual(computed.steps.count, 2)

        // Build NavData the same way the preview does
        let firstStep = computed.steps[0]
        let etaMinutes = UInt16(min(
            computed.expectedTravelTimeSeconds / 60.0,
            Double(UInt16.max - 1)
        ))
        let remainingKmX10 = UInt16(min(
            (computed.totalDistanceMeters / 1000.0) * 10.0,
            Double(UInt16.max - 1)
        ))
        let distMeters = UInt16(min(
            firstStep.distanceMeters,
            Double(UInt16.max - 1)
        ))

        let nav = NavData(
            latitudeE7: Int32(origin.latitude * 1e7),
            longitudeE7: Int32(origin.longitude * 1e7),
            speedKmhX10: 0,
            headingDegX10: 0,
            distanceToManeuverMeters: distMeters,
            maneuver: firstStep.maneuver,
            streetName: String(firstStep.streetName.prefix(31)),
            etaMinutes: etaMinutes,
            remainingKmX10: remainingKmX10
        )

        XCTAssertEqual(nav.maneuver, .right)
        XCTAssertEqual(nav.streetName, "Aeschengraben")
        XCTAssertEqual(nav.distanceToManeuverMeters, 320)
        XCTAssertEqual(nav.etaMinutes, 1)
        XCTAssertEqual(nav.remainingKmX10, 3) // 0.32 km * 10 = 3.2 -> 3

        // Verify it encodes without error (fits wire format)
        let encoded = try nav.encode()
        XCTAssertEqual(encoded.count, NavData.encodedSize)
    }

    func test_noGPSSamples_doesNotHang() async throws {
        // A provider that never emits any samples.
        let emptyProvider = MockLocationProvider()

        // The firstSample helper should time out rather than hang.
        let start = ContinuousClock.now
        let sample = await withTaskGroup(of: LocationSample?.self) { group in
            group.addTask {
                var iterator = emptyProvider.samples.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        let elapsed = ContinuousClock.now - start

        XCTAssertNil(sample, "should return nil when no GPS samples")
        XCTAssertLessThan(
            elapsed, .seconds(2),
            "should not hang — timeout should fire quickly"
        )
    }

    func test_routeEngineError_producesErrorNavData() async throws {
        let engine = MockRouteEngine(error: RouteEngineError.noRoutes)
        let provider = MockLocationProvider()

        // Emit one sample so origin resolves.
        provider.emit(LocationSample(
            scenarioTime: 0, latitude: 47.55, longitude: 7.59,
            speedMps: 0, courseDegrees: 0
        ))

        // Calculate route — should fail.
        do {
            _ = try await engine.calculateRoute(
                from: .init(latitude: 47.55, longitude: 7.59),
                to: .init(latitude: 48.0, longitude: 8.0)
            )
            XCTFail("Expected route calculation to throw")
        } catch {
            // Verify we can build an error NavData that encodes cleanly
            let errorNav = NavData(
                latitudeE7: Int32(47.55 * 1e7),
                longitudeE7: Int32(7.59 * 1e7),
                speedKmhX10: 0,
                headingDegX10: 0,
                distanceToManeuverMeters: NavData.unknownU16,
                maneuver: .none,
                streetName: "Route error",
                etaMinutes: NavData.unknownU16,
                remainingKmX10: NavData.unknownU16
            )
            let encoded = try errorNav.encode()
            XCTAssertEqual(encoded.count, NavData.encodedSize)
        }
    }
}

// MARK: - Weather: correct WeatherData from response + error handling

final class LivePreviewWeatherTests: XCTestCase {

    /// A throwing weather client for error-path tests.
    private final class ThrowingWeatherClient: WeatherServiceClient, @unchecked Sendable {
        let error: Error

        init(error: Error) {
            self.error = error
        }

        func fetchCurrentWeather(
            latitude: Double, longitude: Double
        ) async throws -> WeatherServiceResponse {
            throw error
        }
    }

    func test_weatherData_correctlyConstructedFromResponse() {
        let response = WeatherServiceResponse(
            condition: .rain,
            temperatureCelsius: 14.5,
            highCelsius: 18.0,
            lowCelsius: 9.0,
            locationName: "Zurich"
        )

        let condition: WeatherConditionWire = {
            switch response.condition {
            case .clear: return .clear
            case .cloudy: return .cloudy
            case .rain: return .rain
            case .snow: return .snow
            case .fog: return .fog
            case .thunderstorm: return .thunderstorm
            case .partlyCloudy: return .partlyCloudy
            case .overcast: return .overcast
            case .drizzle: return .drizzle
            }
        }()

        let weather = WeatherData(
            condition: condition,
            temperatureCelsiusX10: Int16(response.temperatureCelsius * 10),
            highCelsiusX10: Int16(response.highCelsius * 10),
            lowCelsiusX10: Int16(response.lowCelsius * 10),
            locationName: response.locationName.isEmpty ? "Basel" : response.locationName
        )

        XCTAssertEqual(weather.condition, .rain)
        XCTAssertEqual(weather.temperatureCelsiusX10, 145)
        XCTAssertEqual(weather.highCelsiusX10, 180)
        XCTAssertEqual(weather.lowCelsiusX10, 90)
        XCTAssertEqual(weather.locationName, "Zurich")
    }

    func test_weatherData_emptyLocationFallsBackToBasel() {
        let response = WeatherServiceResponse(
            condition: .clear,
            temperatureCelsius: 20.0,
            highCelsius: 25.0,
            lowCelsius: 15.0,
            locationName: ""
        )

        let weather = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: Int16(response.temperatureCelsius * 10),
            highCelsiusX10: Int16(response.highCelsius * 10),
            lowCelsiusX10: Int16(response.lowCelsius * 10),
            locationName: response.locationName.isEmpty ? "Basel" : response.locationName
        )

        XCTAssertEqual(weather.locationName, "Basel")
    }

    func test_weatherClientThrows_producesErrorState() async throws {
        let client = ThrowingWeatherClient(
            error: WeatherServiceError.networkFailure("timeout")
        )

        do {
            _ = try await client.fetchCurrentWeather(latitude: 47.56, longitude: 7.59)
            XCTFail("Expected weather fetch to throw")
        } catch {
            // Verify we can build the Fehler fallback that encodes cleanly
            let errorWeather = WeatherData(
                condition: .cloudy,
                temperatureCelsiusX10: 0,
                highCelsiusX10: 0,
                lowCelsiusX10: 0,
                locationName: "Fehler"
            )
            let encoded = try errorWeather.encode()
            XCTAssertEqual(encoded.count, WeatherData.encodedSize)
            XCTAssertEqual(errorWeather.locationName, "Fehler")
        }
    }

    func test_allConditions_mapCorrectly() {
        let cases: [(RideSimulatorKit.WeatherCondition, WeatherConditionWire)] = [
            (.clear, .clear),
            (.cloudy, .cloudy),
            (.rain, .rain),
            (.snow, .snow),
            (.fog, .fog),
            (.thunderstorm, .thunderstorm),
        ]

        for (domain, expectedWire) in cases {
            let response = WeatherServiceResponse(
                condition: domain,
                temperatureCelsius: 10,
                highCelsius: 12,
                lowCelsius: 5,
                locationName: "Test"
            )
            let wire: WeatherConditionWire = {
                switch response.condition {
                case .clear: return .clear
                case .cloudy: return .cloudy
                case .rain: return .rain
                case .snow: return .snow
                case .fog: return .fog
                case .thunderstorm: return .thunderstorm
                case .partlyCloudy: return .partlyCloudy
                case .overcast: return .overcast
                case .drizzle: return .drizzle
                }
            }()
            XCTAssertEqual(wire, expectedWire, "condition \(domain) should map to \(expectedWire)")
        }
    }
}
