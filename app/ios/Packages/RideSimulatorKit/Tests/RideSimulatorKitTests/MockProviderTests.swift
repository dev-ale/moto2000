import XCTest

@testable import RideSimulatorKit

/// Focused tests per provider — each one only proves the channel plumbing
/// works. The scenario player tests cover the timing logic.
final class MockProviderTests: XCTestCase {
    func test_mockLocationProviderDeliversEmittedSamples() async {
        let provider = MockLocationProvider()
        let task = Task { () -> [LocationSample] in
            var out: [LocationSample] = []
            for await sample in provider.samples {
                out.append(sample)
                if out.count == 2 { break }
            }
            return out
        }
        provider.emit(LocationSample(scenarioTime: 0, latitude: 1, longitude: 2))
        provider.emit(LocationSample(scenarioTime: 1, latitude: 3, longitude: 4))
        let delivered = await task.value
        XCTAssertEqual(delivered.map(\.latitude), [1, 3])
    }

    func test_mockWeatherProviderDeliversEmittedSnapshots() async {
        let provider = MockWeatherProvider()
        let task = Task { () -> WeatherSnapshot? in
            for await snapshot in provider.snapshots {
                return snapshot
            }
            return nil
        }
        provider.emit(
            WeatherSnapshot(
                scenarioTime: 0,
                condition: .rain,
                temperatureCelsius: 10,
                highCelsius: 12,
                lowCelsius: 8,
                locationName: "Basel"
            )
        )
        let delivered = await task.value
        XCTAssertEqual(delivered?.condition, .rain)
    }

    func test_simulatorEnvironmentExposesAllMocks() {
        let env = SimulatorEnvironment()
        env.location.emit(LocationSample(scenarioTime: 0, latitude: 0, longitude: 0))
        env.heading.emit(HeadingSample(scenarioTime: 0, magneticDegrees: 0))
        env.motion.emit(MotionSample(scenarioTime: 0, gravityX: 0, gravityY: -1, gravityZ: 0))
    }
}
