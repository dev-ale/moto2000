import XCTest
import BLEProtocol
@testable import RideSimulatorKit

final class BLETransportTests: XCTestCase {
    func testNullTransportAcceptsAnyPayload() async throws {
        let transport = NullBLETransport()
        // Exercises the protocol plumbing. No assertion beyond "does not throw".
        try await transport.send(Data([0x01, 0x02, 0x03]))
        try await transport.send(Data())
    }

    func testHostSimulatorTransportReportsMissingExecutable() async {
        let bogus = URL(fileURLWithPath: "/does/not/exist/scramscreen-host-sim")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bogus.png")
        let transport = HostSimulatorBLETransport(
            executableURL: bogus,
            outputURL: out
        )
        do {
            try await transport.send(Data([0x00]))
            XCTFail("expected simulatorNotFound error")
        } catch let err as HostSimulatorTransportError {
            if case .simulatorNotFound = err {
                // expected
            } else {
                XCTFail("unexpected error: \(err)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testLocateFromEnvironmentReturnsNilWhenUnset() throws {
        // Note: we cannot mutate ProcessInfo safely from a concurrent test,
        // so this asserts the "unset" path only when the variable is in
        // fact unset in the current test environment.
        if ProcessInfo.processInfo.environment["SCRAMSCREEN_HOST_SIM"] == nil {
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("env.png")
            XCTAssertNil(
                HostSimulatorBLETransport.locateFromEnvironment(outputURL: out)
            )
        }
    }

    /// End-to-end: encode a clock payload with the Swift BLEProtocol
    /// codec, ship it through the host simulator transport, assert that a
    /// non-empty PNG lands on disk.
    ///
    /// Skipped automatically when `SCRAMSCREEN_HOST_SIM` is not set
    /// (i.e. on iOS CI and on laptops that have not built the host sim).
    func testEndToEndLoopbackAgainstRealSimulator() async throws {
        guard
            let raw = ProcessInfo.processInfo.environment["SCRAMSCREEN_HOST_SIM"],
            FileManager.default.fileExists(atPath: raw)
        else {
            throw XCTSkip(
                "SCRAMSCREEN_HOST_SIM not set. Build hardware/firmware/host-sim first."
            )
        }

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scramscreen-loopback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outDir) }

        let outputURL = outDir.appendingPathComponent("clock.png")
        let transport = HostSimulatorBLETransport(
            executableURL: URL(fileURLWithPath: raw),
            outputURL: outputURL
        )

        let payload = ScreenPayload.clock(
            ClockData(
                unixTime: 1_738_339_200,
                tzOffsetMinutes: 60,
                is24Hour: true
            ),
            flags: []
        )
        let encoded = try ScreenPayloadCodec.encode(payload)
        try await transport.send(encoded)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "host simulator produced an empty PNG")

        // Very loose PNG sniff: 8-byte magic.
        let head = try Data(contentsOf: outputURL).prefix(8)
        XCTAssertEqual(
            Array(head),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        )
    }
}
