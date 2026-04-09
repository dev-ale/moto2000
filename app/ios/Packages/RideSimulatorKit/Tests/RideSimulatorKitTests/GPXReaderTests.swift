import XCTest

@testable import RideSimulatorKit

final class GPXReaderTests: XCTestCase {
    private let untimedGpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
      <trk><name>basel-loop</name><trkseg>
        <trkpt lat="47.5482" lon="7.5899"><ele>260</ele></trkpt>
        <trkpt lat="47.5485" lon="7.5902"><ele>261</ele></trkpt>
        <trkpt lat="47.5490" lon="7.5910"><ele>262</ele></trkpt>
      </trkseg></trk>
    </gpx>
    """

    private let timedGpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
      <trk><trkseg>
        <trkpt lat="47.5000" lon="7.5000"><time>2025-08-01T10:00:00Z</time></trkpt>
        <trkpt lat="47.5010" lon="7.5010"><time>2025-08-01T10:00:05Z</time></trkpt>
        <trkpt lat="47.5020" lon="7.5020"><time>2025-08-01T10:00:15Z</time></trkpt>
      </trkseg></trk>
    </gpx>
    """

    func test_parsesUntimedGpxWithDefaultSpacing() throws {
        let data = Data(untimedGpx.utf8)
        let samples = try GPXReader.parse(data, defaultSpacing: 2)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.scenarioTime), [0, 2, 4])
        XCTAssertEqual(samples[0].latitude, 47.5482, accuracy: 1e-6)
        XCTAssertEqual(samples[2].altitudeMeters, 262, accuracy: 1e-6)
    }

    func test_parsesTimedGpxAgainstFirstTimestamp() throws {
        let data = Data(timedGpx.utf8)
        let samples = try GPXReader.parse(data)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.scenarioTime), [0, 5, 15])
    }

    func test_parseFailsOnInvalidXml() {
        let data = Data("not-xml".utf8)
        XCTAssertThrowsError(try GPXReader.parse(data))
    }
}
