import XCTest
import BLEProtocol
@testable import ScramCore

final class NavigationRouteTests: XCTestCase {

    func test_codableRoundTrip_preservesAllFields() throws {
        let route = NavigationRoute(
            steps: [
                NavigationRoute.Step(
                    maneuver: .straight,
                    streetName: "Aeschengraben",
                    distanceMeters: 320.0,
                    startLocation: .init(latitude: 47.5482, longitude: 7.5899),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5900)
                ),
                NavigationRoute.Step(
                    maneuver: .left,
                    streetName: "St Alban Rheinweg",
                    distanceMeters: 200.0,
                    startLocation: .init(latitude: 47.5516, longitude: 7.5900),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5870)
                ),
                NavigationRoute.Step(
                    maneuver: .arrive,
                    streetName: "Kaffee Lade",
                    distanceMeters: 0.0,
                    startLocation: .init(latitude: 47.5516, longitude: 7.5870),
                    endLocation: .init(latitude: 47.5516, longitude: 7.5870)
                ),
            ],
            totalDistanceMeters: 520.0,
            expectedTravelTimeSeconds: 120.0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(route)
        let decoded = try JSONDecoder().decode(NavigationRoute.self, from: data)
        XCTAssertEqual(decoded, route)
    }

    func test_maneuverJSONName_roundTripsAllCases() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for maneuver in ManeuverType.allCases {
            let encoded = try encoder.encode([maneuver])
            let decoded = try decoder.decode([ManeuverType].self, from: encoded)
            XCTAssertEqual(decoded.first, maneuver)
        }
    }

    func test_loadRouteFixtureFromBundle_decodesSuccessfully() throws {
        let route = try Self.loadRouteFixture(named: "three-step-straight-left")
        XCTAssertEqual(route.steps.count, 3)
        XCTAssertEqual(route.steps[0].maneuver, .straight)
        XCTAssertEqual(route.steps[1].maneuver, .left)
        XCTAssertEqual(route.steps[2].maneuver, .arrive)
        XCTAssertEqual(route.totalDistanceMeters, 700.0, accuracy: 0.001)
    }

    // MARK: - Helpers

    static func loadRouteFixture(named name: String) throws -> NavigationRoute {
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: name,
            withExtension: "route.json",
            subdirectory: "Fixtures/routes"
        ) ?? bundle.url(
            forResource: "\(name).route",
            withExtension: "json",
            subdirectory: "Fixtures/routes"
        ) else {
            XCTFail("route fixture not found: \(name)")
            throw NSError(domain: "NavigationRouteTests", code: 1)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NavigationRoute.self, from: data)
    }
}
