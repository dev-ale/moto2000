import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScramCore

final class NavigationServiceTests: XCTestCase {

    func test_scriptedSamples_emitMonotonicallyAdvancingSteps() async throws {
        let route = try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
        let engine = StaticRouteEngine(fixedRoute: route)
        let provider = MockLocationProvider()
        let service = NavigationService(
            routeEngine: engine,
            locationProvider: provider
        )

        // Script a sample sequence that walks end-to-end through all
        // three steps. The first sample is consumed as origin and is
        // also emitted as a payload.
        let samples: [LocationSample] = [
            LocationSample(scenarioTime: 0, latitude: 47.5480, longitude: 7.5900,
                           speedMps: 10.0, courseDegrees: 0.0),
            LocationSample(scenarioTime: 5, latitude: 47.5498, longitude: 7.5900,
                           speedMps: 10.0, courseDegrees: 0.0),
            LocationSample(scenarioTime: 10, latitude: 47.5516, longitude: 7.5900,
                           speedMps: 10.0, courseDegrees: 0.0),
            LocationSample(scenarioTime: 15, latitude: 47.5516, longitude: 7.5880,
                           speedMps: 10.0, courseDegrees: 270.0),
            LocationSample(scenarioTime: 20, latitude: 47.5516, longitude: 7.5860,
                           speedMps: 0.0, courseDegrees: 270.0),
        ]

        let collector = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.navDataPayloads {
                out.append(blob)
                if out.count == samples.count { return out }
            }
            return out
        }

        // Start BEFORE emitting so the service picks up the first sample
        // as origin and every subsequent sample funnels through.
        try await service.start(destination: .init(latitude: 47.5516, longitude: 7.5860))

        // Give the consumer task a tick to install its iterator.
        try await Task.sleep(nanoseconds: 20_000_000)
        for sample in samples {
            provider.emit(sample)
        }
        // Wait for the collector to gather everything.
        try await Task.sleep(nanoseconds: 100_000_000)
        await provider.stop()
        await service.stop()

        let received = await collector.value
        XCTAssertEqual(received.count, samples.count)

        var lastStepIndex = -1
        var stepIndices: [Int] = []
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .navigation(let nav, _) = payload else {
                XCTFail("expected navigation payload")
                return
            }
            // Infer step index via maneuver: 0 = straight, 1 = left, 2 = arrive.
            let stepIndex: Int
            switch nav.maneuver {
            case .straight: stepIndex = 0
            case .left: stepIndex = 1
            case .arrive: stepIndex = 2
            default: stepIndex = -1
            }
            stepIndices.append(stepIndex)
            XCTAssertGreaterThanOrEqual(stepIndex, lastStepIndex,
                                        "step index went backwards: \(stepIndices)")
            lastStepIndex = stepIndex
        }
        // We should have seen all three maneuvers fire at some point.
        XCTAssertTrue(stepIndices.contains(0))
        XCTAssertTrue(stepIndices.contains(1))
        XCTAssertTrue(stepIndices.contains(2))
    }
}
