// swift-tools-version: 6.0
import PackageDescription

/// BLEProtocol — Swift encoder/decoder for the ScramScreen BLE wire format.
///
/// The wire format is defined in `docs/ble-protocol.md`. This package and the C
/// component at `hardware/firmware/components/ble_protocol/` are validated
/// against the same golden fixtures in `protocol/fixtures/` so that a payload
/// encoded on the iPhone decodes byte-for-byte identically on the ESP32.
let package = Package(
    name: "BLEProtocol",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "BLEProtocol",
            targets: ["BLEProtocol"]
        ),
    ],
    targets: [
        .target(
            name: "BLEProtocol",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "BLEProtocolTests",
            dependencies: ["BLEProtocol"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
