import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScramCore

final class RouteTrackerTests: XCTestCase {

    // MARK: - Single straight step

    func test_singleStraightStep_distanceDecreasesMonotonically() async {
        let route = NavigationRoute(
            steps: [
                NavigationRoute.Step(
                    maneuver: .straight,
                    streetName: "STRAIGHT ST",
                    distanceMeters: 400.0,
                    startLocation: .init(latitude: 47.5480, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5900)
                )
            ],
            totalDistanceMeters: 400.0,
            expectedTravelTimeSeconds: 80.0
        )
        let tracker = RouteTracker(route: route)

        // Move north in ~60m chunks from 47.5480 towards 47.5516.
        let samples: [LocationSample] = (0...6).map { i in
            let lat = 47.5480 + Double(i) * 0.0006
            return LocationSample(
                scenarioTime: Double(i) * 10.0,
                latitude: lat,
                longitude: 7.5900,
                altitudeMeters: 260,
                speedMps: 12.0,
                courseDegrees: 0.0
            )
        }

        var lastDistance: Double = .infinity
        for sample in samples {
            let state = await tracker.update(with: sample)
            XCTAssertEqual(state.currentStepIndex, 0)
            XCTAssertLessThanOrEqual(state.distanceToNextManeuverMeters, lastDistance + 0.01)
            lastDistance = state.distanceToNextManeuverMeters
            XCTAssertEqual(state.currentManeuver, .straight)
        }
    }

    // MARK: - Multi-step: straight → left → arrive

    func test_multiStep_advancesAtEachStepEnd() async throws {
        let route = try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
        let tracker = RouteTracker(route: route)

        // Sample 1: near origin → step 0.
        var state = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5480, longitude: 7.5900,
            speedMps: 10.0, courseDegrees: 0.0
        ))
        XCTAssertEqual(state.currentStepIndex, 0)
        XCTAssertEqual(state.currentManeuver, .straight)

        // Sample 2: near the end of step 0 (should advance to step 1).
        state = await tracker.update(with: LocationSample(
            scenarioTime: 10, latitude: 47.5516, longitude: 7.5900,
            speedMps: 10.0, courseDegrees: 0.0
        ))
        XCTAssertEqual(state.currentStepIndex, 1)
        XCTAssertEqual(state.currentManeuver, .left)

        // Sample 3: midway through step 1 — still step 1.
        state = await tracker.update(with: LocationSample(
            scenarioTime: 20, latitude: 47.5516, longitude: 7.5880,
            speedMps: 10.0, courseDegrees: 270.0
        ))
        XCTAssertEqual(state.currentStepIndex, 1)

        // Sample 4: at arrive point — advances to step 2 (arrive).
        state = await tracker.update(with: LocationSample(
            scenarioTime: 30, latitude: 47.5516, longitude: 7.5860,
            speedMps: 0.0, courseDegrees: 270.0
        ))
        XCTAssertEqual(state.currentStepIndex, 2)
        XCTAssertEqual(state.currentManeuver, .arrive)
    }

    // MARK: - Edge: past end of last step → clamps to arrive

    func test_pastEndOfLastStep_clampsToArrive() async throws {
        let route = try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
        let tracker = RouteTracker(route: route)

        // Walk to the arrive point first so the tracker advances.
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5480, longitude: 7.5900
        ))
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 1, latitude: 47.5516, longitude: 7.5900
        ))
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 2, latitude: 47.5516, longitude: 7.5860
        ))
        // Now blow past the destination.
        let state = await tracker.update(with: LocationSample(
            scenarioTime: 3, latitude: 47.5516, longitude: 7.5800
        ))
        XCTAssertEqual(state.currentStepIndex, 2)
        XCTAssertEqual(state.currentManeuver, .arrive)
    }

    // MARK: - Edge: location before first step → stays at step 0

    func test_beforeFirstStep_staysAtStepZero() async throws {
        let route = try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
        let tracker = RouteTracker(route: route)

        let state = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5450, longitude: 7.5900
        ))
        XCTAssertEqual(state.currentStepIndex, 0)
    }

    // MARK: - Off-route tolerance

    func test_offRoute50m_stillUsesCurrentStep() async throws {
        let route = try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
        let tracker = RouteTracker(route: route)

        // 50m east of the start of step 0.
        let state = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5480, longitude: 7.5907
        ))
        XCTAssertEqual(state.currentStepIndex, 0)
        XCTAssertEqual(state.currentManeuver, .straight)
        // Distance should be finite and > 0.
        XCTAssertGreaterThan(state.distanceToNextManeuverMeters, 0)
    }

    // MARK: - Haversine sanity

    func test_haversine_knownDistance() {
        // 1 degree of latitude ≈ 111 km.
        let d = RouteTracker.haversineMeters(
            lat1: 0, lon1: 0, lat2: 1, lon2: 0
        )
        XCTAssertEqual(d, 111_195.0, accuracy: 50.0)
    }
}
