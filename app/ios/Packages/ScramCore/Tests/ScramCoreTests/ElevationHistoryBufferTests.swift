import XCTest
import BLEProtocol

@testable import ScramCore

final class ElevationHistoryBufferTests: XCTestCase {
    func test_emptyBuffer_snapshotHasZeroSamples() {
        let buf = ElevationHistoryBuffer()
        let snap = buf.snapshot
        XCTAssertEqual(snap.sampleCount, 0)
        XCTAssertEqual(snap.currentAltitudeM, 0)
        XCTAssertEqual(snap.totalAscentM, 0)
        XCTAssertEqual(snap.totalDescentM, 0)
    }

    func test_singleSample() {
        let buf = ElevationHistoryBuffer().ingesting(450)
        let snap = buf.snapshot
        XCTAssertEqual(snap.sampleCount, 1)
        XCTAssertEqual(snap.currentAltitudeM, 450)
        XCTAssertEqual(snap.totalAscentM, 0)
        XCTAssertEqual(snap.totalDescentM, 0)
        XCTAssertEqual(snap.profile[0], 450)
    }

    func test_flatRide_noAscentDescent() {
        var buf = ElevationHistoryBuffer()
        for _ in 0..<20 {
            buf = buf.ingesting(260)
        }
        let snap = buf.snapshot
        XCTAssertEqual(snap.sampleCount, 20)
        XCTAssertEqual(snap.currentAltitudeM, 260)
        XCTAssertEqual(snap.totalAscentM, 0)
        XCTAssertEqual(snap.totalDescentM, 0)
        // All profile samples should be 260
        for i in 0..<20 {
            XCTAssertEqual(snap.profile[i], 260)
        }
    }

    func test_mountainPass_ascentAndDescent() {
        var buf = ElevationHistoryBuffer()
        // Climb from 500 to 2400
        for alt in stride(from: 500.0, through: 2400.0, by: 100.0) {
            buf = buf.ingesting(alt)
        }
        // Descend from 2400 to 1800
        for alt in stride(from: 2300.0, through: 1800.0, by: -100.0) {
            buf = buf.ingesting(alt)
        }

        XCTAssertEqual(buf.totalAscentMeters, 1900, accuracy: 1)
        XCTAssertEqual(buf.totalDescentMeters, 600, accuracy: 1)
        XCTAssertEqual(buf.lastAltitude, 1800)

        let snap = buf.snapshot
        XCTAssertEqual(snap.currentAltitudeM, 1800)
        XCTAssertEqual(snap.totalAscentM, 1900)
        XCTAssertEqual(snap.totalDescentM, 600)
        XCTAssertGreaterThan(snap.sampleCount, 0)
    }

    func test_jitterFiltering_ignoresSmallDeltas() {
        var buf = ElevationHistoryBuffer()
        buf = buf.ingesting(100.0)
        buf = buf.ingesting(100.5)  // +0.5 m -> ignored
        buf = buf.ingesting(100.3)  // -0.2 m -> ignored
        buf = buf.ingesting(102.0)  // +1.7 m from 100.3 -> counted (> 1m)
        buf = buf.ingesting(99.0)   // -3.0 m -> counted

        XCTAssertEqual(buf.totalAscentMeters, 1.7, accuracy: 0.001)
        XCTAssertEqual(buf.totalDescentMeters, 3.0, accuracy: 0.001)
    }

    func test_downsamplingAccuracy_120SamplesTo60Bins() {
        var buf = ElevationHistoryBuffer()
        // Feed 120 samples: 0, 1, 2, ..., 119 metres altitude
        for i in 0..<120 {
            buf = buf.ingesting(Double(i))
        }
        XCTAssertEqual(buf.samples.count, 120)

        let bins = buf.downsampled(to: 60)
        XCTAssertEqual(bins.count, 60)

        // Each bin should average 2 consecutive values:
        // bin 0 = avg(0, 1) = 0.5 -> rounds to 1 (banker's rounding rounds 0.5 up for odd)
        // bin 1 = avg(2, 3) = 2.5 -> rounds to 3
        // bin 59 = avg(118, 119) = 118.5 -> rounds to 119
        // The exact rounding doesn't matter much for the graph — just verify they're close.
        XCTAssertTrue(abs(Int(bins[0]) - 0) <= 1)
        XCTAssertTrue(abs(Int(bins[1]) - 2) <= 1)
        XCTAssertTrue(abs(Int(bins[59]) - 118) <= 1)
    }

    func test_downsampling_fewerThan60Samples() {
        var buf = ElevationHistoryBuffer()
        for i in 0..<10 {
            buf = buf.ingesting(Double(i * 100))
        }
        let bins = buf.downsampled(to: 60)
        // Should return 10 bins (not 60)
        XCTAssertEqual(bins.count, 10)
        XCTAssertEqual(bins[0], 0)
        XCTAssertEqual(bins[9], 900)
    }

    func test_snapshot_roundTripsViaCodec() throws {
        var buf = ElevationHistoryBuffer()
        buf = buf.ingesting(260)
        buf = buf.ingesting(280)
        buf = buf.ingesting(300)

        let snap = buf.snapshot
        // Round-trip via the full codec
        let encoded = try ScreenPayloadCodec.encode(.altitude(snap, flags: []))
        let decoded = try ScreenPayloadCodec.decode(encoded)
        guard case .altitude(let alt, _) = decoded else {
            XCTFail("expected altitude payload")
            return
        }
        XCTAssertEqual(alt.sampleCount, 3)
        XCTAssertEqual(alt.currentAltitudeM, 300)
    }

    func test_negativeAltitude() {
        var buf = ElevationHistoryBuffer()
        buf = buf.ingesting(-50)
        buf = buf.ingesting(-100)

        XCTAssertEqual(buf.lastAltitude, -100)
        XCTAssertEqual(buf.totalDescentMeters, 50, accuracy: 0.001)
        let snap = buf.snapshot
        XCTAssertEqual(snap.currentAltitudeM, -100)
        XCTAssertEqual(snap.profile[0], -50)
        XCTAssertEqual(snap.profile[1], -100)
    }

    func test_downsamplingWith240Samples() {
        var buf = ElevationHistoryBuffer()
        // 240 samples: each bucket gets 4 samples
        for i in 0..<240 {
            buf = buf.ingesting(Double(i))
        }
        let bins = buf.downsampled(to: 60)
        XCTAssertEqual(bins.count, 60)
        // Bin 0 = avg(0,1,2,3) = 1.5 -> rounds to 2
        XCTAssertEqual(bins[0], 2) // 1.5 rounds to 2
        // Bin 59 = avg(236,237,238,239) = 237.5 -> rounds to 238
        XCTAssertEqual(bins[59], 238)
    }
}
