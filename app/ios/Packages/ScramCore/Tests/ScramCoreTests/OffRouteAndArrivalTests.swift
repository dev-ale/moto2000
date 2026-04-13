import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScramCore

final class OffRouteAndArrivalTests: XCTestCase {

    // MARK: - Helpers

    /// Three-step route running north then west in Basel.
    private func threeStepRoute() throws -> NavigationRoute {
        try NavigationRouteTests.loadRouteFixture(named: "three-step-straight-left")
    }

    // MARK: - Off-route detection

    func test_onRoute_isOffRouteFalse() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Feed samples that are ON the route (near step start/end points).
        for idx in 0..<15 {
            _ = await tracker.update(with: LocationSample(
                scenarioTime: Double(idx),
                latitude: 47.5480 + Double(idx) * 0.0002,
                longitude: 7.5900,
                speedMps: 10.0, courseDegrees: 0.0
            ))
        }
        let offRoute = await tracker.isOffRoute
        XCTAssertFalse(offRoute, "rider on route should not be flagged off-route")
    }

    func test_offRoute_flagsTrueAfterThreshold() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Feed samples far from the route (shifted ~500m east).
        for idx in 0..<RouteTracker.offRouteConsecutiveThreshold + 1 {
            _ = await tracker.update(with: LocationSample(
                scenarioTime: Double(idx),
                latitude: 47.5480,
                longitude: 7.6000, // ~700m east of route
                speedMps: 10.0, courseDegrees: 0.0
            ))
        }
        let offRoute = await tracker.isOffRoute
        XCTAssertTrue(offRoute, "rider far from route for enough samples should be flagged off-route")
    }

    func test_offRoute_resetsWhenReturningToRoute() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Go off-route.
        for idx in 0..<RouteTracker.offRouteConsecutiveThreshold + 1 {
            _ = await tracker.update(with: LocationSample(
                scenarioTime: Double(idx),
                latitude: 47.5480,
                longitude: 7.6000,
                speedMps: 10.0, courseDegrees: 0.0
            ))
        }
        let flagged = await tracker.isOffRoute
        XCTAssertTrue(flagged)

        // Return to the route.
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 20,
            latitude: 47.5480,
            longitude: 7.5900,
            speedMps: 10.0, courseDegrees: 0.0
        ))
        let cleared = await tracker.isOffRoute
        XCTAssertFalse(cleared, "off-route flag should clear when rider returns")
    }

    func test_offRoute_belowThresholdCount_staysFalse() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Only send threshold - 1 off-route samples.
        for idx in 0..<RouteTracker.offRouteConsecutiveThreshold - 1 {
            _ = await tracker.update(with: LocationSample(
                scenarioTime: Double(idx),
                latitude: 47.5480,
                longitude: 7.6000,
                speedMps: 10.0, courseDegrees: 0.0
            ))
        }
        let offRoute = await tracker.isOffRoute
        XCTAssertFalse(offRoute, "fewer than threshold off-route samples should not trigger")
    }

    // MARK: - Arrival detection

    func test_arrival_detectedAtLastStep() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Walk the route to the arrive step.
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5480, longitude: 7.5900
        ))
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 1, latitude: 47.5516, longitude: 7.5900
        ))
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 2, latitude: 47.5516, longitude: 7.5860
        ))

        // Now sit at the destination.
        let state = await tracker.update(with: LocationSample(
            scenarioTime: 3, latitude: 47.5516, longitude: 7.5860
        ))
        XCTAssertEqual(state.currentManeuver, .arrive)
        let arrived = await tracker.hasArrived
        XCTAssertTrue(arrived, "should detect arrival at destination")
    }

    func test_arrival_notFlaggedMidRoute() async throws {
        let route = try threeStepRoute()
        let tracker = RouteTracker(route: route)

        // Only at step 0 — far from destination.
        _ = await tracker.update(with: LocationSample(
            scenarioTime: 0, latitude: 47.5490, longitude: 7.5900,
            speedMps: 10.0, courseDegrees: 0.0
        ))
        let arrived = await tracker.hasArrived
        XCTAssertFalse(arrived, "should not flag arrival while mid-route")
    }

    // MARK: - Reroute trigger via NavigationService

    func test_reroute_triggeredWhenOffRoute() async throws {
        let engine = SequentialRouteEngine(routes: [
            Self.makeOriginalRoute(),
            Self.makeReroutedRoute(),
        ])
        let provider = MockLocationProvider()
        let service = NavigationService(routeEngine: engine, locationProvider: provider)

        let collector = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.navDataPayloads {
                out.append(blob)
                if out.count >= RouteTracker.offRouteConsecutiveThreshold + 3 { return out }
            }
            return out
        }

        try await service.start(destination: .init(latitude: 47.5570, longitude: 7.5900))
        try await Task.sleep(nanoseconds: 20_000_000)

        // Emit samples far east (off-route from original).
        for idx in 0..<RouteTracker.offRouteConsecutiveThreshold + 3 {
            provider.emit(LocationSample(
                scenarioTime: Double(idx), latitude: 47.5480,
                longitude: 7.6000, speedMps: 10.0, courseDegrees: 90.0
            ))
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        await provider.stop()
        await service.stop()

        let received = await collector.value
        XCTAssertGreaterThanOrEqual(received.count, 2, "should have received payloads after reroute")

        let callCount = await engine.callCount
        XCTAssertGreaterThanOrEqual(callCount, 2, "engine should be called again for reroute")
    }

    // MARK: - Arrival stops payloads

    func test_arrival_stopsPayloads() async throws {
        let route = try threeStepRoute()
        let engine = StaticRouteEngine(fixedRoute: route)
        let provider = MockLocationProvider()
        let service = NavigationService(
            routeEngine: engine,
            locationProvider: provider
        )

        let collector = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.navDataPayloads {
                out.append(blob)
            }
            return out
        }

        try await service.start(
            destination: .init(latitude: 47.5516, longitude: 7.5860)
        )
        try await Task.sleep(nanoseconds: 20_000_000)

        // Walk to arrival.
        let samples: [LocationSample] = [
            LocationSample(scenarioTime: 0, latitude: 47.5480, longitude: 7.5900,
                           speedMps: 10.0, courseDegrees: 0.0),
            LocationSample(scenarioTime: 5, latitude: 47.5516, longitude: 7.5900,
                           speedMps: 10.0, courseDegrees: 0.0),
            LocationSample(scenarioTime: 10, latitude: 47.5516, longitude: 7.5860,
                           speedMps: 0.0, courseDegrees: 270.0),
            // Extra sample after arrival — should NOT produce a payload
            // because the loop breaks on arrival.
            LocationSample(scenarioTime: 15, latitude: 47.5516, longitude: 7.5850,
                           speedMps: 10.0, courseDegrees: 270.0),
        ]

        for sample in samples {
            provider.emit(sample)
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        await provider.stop()
        await service.stop()

        let received = await collector.value
        // Arrival should cap the emission at or near the arrival sample.
        // Depending on tracker timing, this is either 3 (first fix +
        // sample 1 + arrival sample) or 4 (plus one post-arrival sample
        // that slipped through before the tracker flipped hasArrived).
        // Anything beyond 4 means arrival isn't stopping the loop at all.
        XCTAssertLessThanOrEqual(received.count, 4,
            "arrival should stop payloads soon after; got \(received.count)")
        XCTAssertGreaterThanOrEqual(received.count, 3)
    }
    // MARK: - Route fixtures

    private static func makeOriginalRoute() -> NavigationRoute {
        NavigationRoute(
            steps: [
                NavigationRoute.Step(
                    maneuver: .straight, streetName: "Original St",
                    distanceMeters: 1000.0,
                    startLocation: .init(latitude: 47.5480, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5570, longitude: 7.5900)
                ),
                NavigationRoute.Step(
                    maneuver: .arrive, streetName: "Destination",
                    distanceMeters: 0.0,
                    startLocation: .init(latitude: 47.5570, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5570, longitude: 7.5900)
                ),
            ],
            totalDistanceMeters: 1000.0,
            expectedTravelTimeSeconds: 200.0
        )
    }

    private static func makeReroutedRoute() -> NavigationRoute {
        NavigationRoute(
            steps: [
                NavigationRoute.Step(
                    maneuver: .straight, streetName: "Rerouted St",
                    distanceMeters: 500.0,
                    startLocation: .init(latitude: 47.5480, longitude: 7.6000),
                    endLocation: .init(latitude: 47.5570, longitude: 7.5900)
                ),
                NavigationRoute.Step(
                    maneuver: .arrive, streetName: "Destination",
                    distanceMeters: 0.0,
                    startLocation: .init(latitude: 47.5570, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5570, longitude: 7.5900)
                ),
            ],
            totalDistanceMeters: 500.0,
            expectedTravelTimeSeconds: 100.0
        )
    }
}

// MARK: - SequentialRouteEngine

/// Test engine that returns a different route on each call.
private actor SequentialRouteEngine: RouteEngine {
    private let routes: [NavigationRoute]
    private var index: Int = 0
    private(set) var callCount: Int = 0

    init(routes: [NavigationRoute]) {
        self.routes = routes
    }

    func calculateRoute(
        from origin: NavigationRoute.LocationCoordinate,
        to destination: NavigationRoute.LocationCoordinate
    ) async throws -> NavigationRoute {
        callCount += 1
        let route = routes[min(index, routes.count - 1)]
        index += 1
        return route
    }
}
