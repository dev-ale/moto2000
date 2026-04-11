import Foundation
import XCTest

@testable import ScramCore

final class GPXExporterTests: XCTestCase {

    // MARK: - Valid XML structure

    func test_export_producesValidXMLStructure() throws {
        let points = [
            RoutePoint(latitude: 47.5540, longitude: 7.5889),
            RoutePoint(latitude: 47.5543, longitude: 7.5892),
        ]
        let gpx = GPXExporter.export(points: points)

        // Parse as XML to verify validity
        let doc = try XMLDocument(xmlString: gpx)
        let root = try XCTUnwrap(doc.rootElement())
        XCTAssertEqual(root.name, "gpx")
        XCTAssertEqual(root.attribute(forName: "version")?.stringValue, "1.1")
        XCTAssertEqual(root.attribute(forName: "creator")?.stringValue, "ScramScreen")
    }

    // MARK: - Route points as trkpt

    func test_export_routePointsAppearAsTrkpt() throws {
        let points = [
            RoutePoint(latitude: 47.5540, longitude: 7.5889),
            RoutePoint(latitude: 47.5543, longitude: 7.5892),
            RoutePoint(latitude: 47.5550, longitude: 7.5900),
        ]
        let gpx = GPXExporter.export(points: points)

        let doc = try XMLDocument(xmlString: gpx)
        let trkpts = try doc.nodes(forXPath: "//trkpt")
        XCTAssertEqual(trkpts.count, 3)

        let first = try XCTUnwrap(trkpts.first as? XMLElement)
        XCTAssertEqual(first.attribute(forName: "lat")?.stringValue, "47.554000")
        XCTAssertEqual(first.attribute(forName: "lon")?.stringValue, "7.588900")
    }

    // MARK: - Metadata with trip

    func test_export_includesTripNameAndDate() throws {
        let date = ISO8601DateFormatter().date(from: "2026-04-11T14:30:00Z")!
        let trip = TripSummary(
            date: date,
            duration: 3600,
            distanceKm: 42.0,
            avgSpeedKmh: 42.0,
            maxSpeedKmh: 80.0,
            elevationGainM: 500
        )
        let points = [RoutePoint(latitude: 47.554, longitude: 7.589)]
        let gpx = GPXExporter.export(points: points, trip: trip)

        let doc = try XMLDocument(xmlString: gpx)
        let nameNodes = try doc.nodes(forXPath: "//metadata/name")
        let nameValue = try XCTUnwrap(nameNodes.first?.stringValue)
        XCTAssertTrue(nameValue.contains("April 11, 2026"), "Metadata name should contain the date")
        XCTAssertTrue(nameValue.hasPrefix("Ride"), "Metadata name should start with Ride")

        let timeNodes = try doc.nodes(forXPath: "//metadata/time")
        let timeValue = try XCTUnwrap(timeNodes.first?.stringValue)
        XCTAssertTrue(timeValue.contains("2026-04-11"), "Metadata time should contain the date")
    }

    // MARK: - Elevation in GPX

    func test_export_includesElevationWhenAvailable() throws {
        let points = [
            RoutePoint(latitude: 47.554, longitude: 7.589, altitude: 320.5),
            RoutePoint(latitude: 47.555, longitude: 7.590, altitude: 325.0),
            RoutePoint(latitude: 47.556, longitude: 7.591),  // no altitude
        ]
        let gpx = GPXExporter.export(points: points)

        let doc = try XMLDocument(xmlString: gpx)
        let eleNodes = try doc.nodes(forXPath: "//trkpt/ele")
        XCTAssertEqual(eleNodes.count, 2, "Only points with altitude should have <ele>")
        XCTAssertEqual(eleNodes[0].stringValue, "320.5")
        XCTAssertEqual(eleNodes[1].stringValue, "325.0")
    }

    // MARK: - Empty points

    func test_export_emptyPoints_producesValidGPX() throws {
        let gpx = GPXExporter.export(points: [])
        let doc = try XMLDocument(xmlString: gpx)
        let trkpts = try doc.nodes(forXPath: "//trkpt")
        XCTAssertEqual(trkpts.count, 0)
    }
}
