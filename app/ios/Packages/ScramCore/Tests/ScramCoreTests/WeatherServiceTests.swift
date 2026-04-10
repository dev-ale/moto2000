import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class WeatherServiceTests: XCTestCase {
    func test_encode_mapsAllConditions() throws {
        let provider = MockWeatherProvider()
        let service = WeatherService(provider: provider)

        let cases: [(WeatherCondition, WeatherConditionWire)] = [
            (.clear, .clear),
            (.cloudy, .cloudy),
            (.rain, .rain),
            (.snow, .snow),
            (.fog, .fog),
            (.thunderstorm, .thunderstorm),
        ]
        for (domain, wire) in cases {
            let snapshot = WeatherSnapshot(
                scenarioTime: 0,
                condition: domain,
                temperatureCelsius: 10,
                highCelsius: 12,
                lowCelsius: 5,
                locationName: "Basel"
            )
            let blob = try XCTUnwrap(service.encode(snapshot))
            let decoded = try ScreenPayloadCodec.decode(blob)
            guard case .weather(let data, _) = decoded else {
                XCTFail("expected weather payload for \(domain)")
                return
            }
            XCTAssertEqual(data.condition, wire)
        }
    }

    func test_encode_clampsTemperatureRange() throws {
        let provider = MockWeatherProvider()
        let service = WeatherService(provider: provider)

        // 100°C should clamp to the 60°C maximum (600 × 10).
        let hot = WeatherSnapshot(
            scenarioTime: 0, condition: .clear,
            temperatureCelsius: 100, highCelsius: 110, lowCelsius: 90,
            locationName: "Hot"
        )
        let hotBlob = try XCTUnwrap(service.encode(hot))
        if case .weather(let data, _) = try ScreenPayloadCodec.decode(hotBlob) {
            XCTAssertEqual(data.temperatureCelsiusX10, WeatherData.maxTemperatureX10)
            XCTAssertEqual(data.highCelsiusX10, WeatherData.maxTemperatureX10)
            XCTAssertEqual(data.lowCelsiusX10, WeatherData.maxTemperatureX10)
        } else {
            XCTFail("expected weather payload")
        }

        // -100°C should clamp to -50°C (-500 × 10).
        let cold = WeatherSnapshot(
            scenarioTime: 0, condition: .snow,
            temperatureCelsius: -100, highCelsius: -90, lowCelsius: -110,
            locationName: "Cold"
        )
        let coldBlob = try XCTUnwrap(service.encode(cold))
        if case .weather(let data, _) = try ScreenPayloadCodec.decode(coldBlob) {
            XCTAssertEqual(data.temperatureCelsiusX10, WeatherData.minTemperatureX10)
            XCTAssertEqual(data.lowCelsiusX10, WeatherData.minTemperatureX10)
        } else {
            XCTFail("expected weather payload")
        }
    }

    func test_encode_truncatesLongLocationName() throws {
        let provider = MockWeatherProvider()
        let service = WeatherService(provider: provider)
        let snapshot = WeatherSnapshot(
            scenarioTime: 0, condition: .clear,
            temperatureCelsius: 20, highCelsius: 25, lowCelsius: 15,
            locationName: String(repeating: "A", count: 40)
        )
        let blob = try XCTUnwrap(service.encode(snapshot))
        if case .weather(let data, _) = try ScreenPayloadCodec.decode(blob) {
            XCTAssertLessThanOrEqual(data.locationName.utf8.count, 19)
            XCTAssertEqual(data.locationName, String(repeating: "A", count: 19))
        } else {
            XCTFail("expected weather payload")
        }
    }

    func test_service_forwardsSnapshotsThroughStream() async throws {
        let provider = MockWeatherProvider()
        let service = WeatherService(provider: provider)
        service.start()

        let stream = service.encodedPayloads
        let collector = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in stream {
                out.append(blob)
                if out.count == 2 { return out }
            }
            return out
        }

        provider.emit(WeatherSnapshot(
            scenarioTime: 0, condition: .clear,
            temperatureCelsius: 22, highCelsius: 25, lowCelsius: 13,
            locationName: "Basel"
        ))
        provider.emit(WeatherSnapshot(
            scenarioTime: 60, condition: .rain,
            temperatureCelsius: 14.5, highCelsius: 17, lowCelsius: 11,
            locationName: "Paris"
        ))

        try await Task.sleep(nanoseconds: 50_000_000)
        await provider.stop()
        service.stop()

        let received = await collector.value
        XCTAssertEqual(received.count, 2)

        let first = try ScreenPayloadCodec.decode(received[0])
        let second = try ScreenPayloadCodec.decode(received[1])
        guard case .weather(let a, _) = first,
              case .weather(let b, _) = second else {
            XCTFail("expected two weather payloads")
            return
        }
        XCTAssertEqual(a.condition, .clear)
        XCTAssertEqual(a.temperatureCelsiusX10, 220)
        XCTAssertEqual(a.locationName, "Basel")
        XCTAssertEqual(b.condition, .rain)
        XCTAssertEqual(b.temperatureCelsiusX10, 145)
        XCTAssertEqual(b.locationName, "Paris")
    }
}
