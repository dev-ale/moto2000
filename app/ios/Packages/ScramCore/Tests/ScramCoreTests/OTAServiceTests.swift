import BLEProtocol
import XCTest

@testable import ScramCore

final class OTAServiceTests: XCTestCase {

    /// Drain `count` commands from the service's stream into an array.
    private func drain(_ service: OTAService, count: Int) async -> [ControlCommand] {
        var seen: [ControlCommand] = []
        var iterator = service.commands.makeAsyncIterator()
        for _ in 0..<count {
            if let next = await iterator.next() {
                seen.append(next)
            }
        }
        return seen
    }

    func test_checkForUpdate_emits_checkForOTAUpdate_command() async {
        let service = OTAService()
        await service.checkForUpdate()
        let commands = await drain(service, count: 1)
        XCTAssertEqual(commands, [.checkForOTAUpdate])
    }

    func test_setCurrentVersion() async {
        let service = OTAService()
        let version = FirmwareVersion(major: 1, minor: 2, patch: 3)
        await service.setCurrentVersion(version)
        let current = await service.currentVersion
        XCTAssertEqual(current, version)
    }

    func test_initialVersion_is_nil() async {
        let service = OTAService()
        let current = await service.currentVersion
        XCTAssertNil(current)
    }

    func test_multiple_checks_emit_multiple_commands() async {
        let service = OTAService()
        await service.checkForUpdate()
        await service.checkForUpdate()
        let commands = await drain(service, count: 2)
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands.allSatisfy { $0 == .checkForOTAUpdate })
    }

    func test_checkForOTAUpdate_encodes_to_four_bytes() async {
        let service = OTAService()
        await service.checkForUpdate()
        let commands = await drain(service, count: 1)
        XCTAssertEqual(commands.first?.encode().count, 4)
    }

    func test_checkForOTAUpdate_encoded_bytes() async {
        let service = OTAService()
        await service.checkForUpdate()
        let commands = await drain(service, count: 1)
        let bytes = commands.first!.encode()
        XCTAssertEqual(Array(bytes), [0x01, 0x06, 0x00, 0x00])
    }
}
