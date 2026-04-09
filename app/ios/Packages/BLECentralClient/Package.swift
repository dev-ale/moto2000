// swift-tools-version: 6.0
import PackageDescription

/// BLECentralClient — iOS side of Slice 17 (auto-reconnect + disconnect resilience).
///
/// Wraps `CoreBluetooth` behind the ``BLECentralClient`` protocol and layers
/// a pure-Swift reconnect state machine and last-known payload cache on top.
/// Every type in this package is designed to be host-testable without any
/// real BLE peripheral, by driving events through ``TestBLECentralClient`` and
/// advancing a ``VirtualClock`` from `RideSimulatorKit`.
///
/// The actual `CBCentralManager` wiring lives in the thin
/// ``CoreBluetoothCentralClient`` stub and is fleshed out in a later slice
/// that runs on real hardware.
let package = Package(
    name: "BLECentralClient",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "BLECentralClient",
            targets: ["BLECentralClient"]
        ),
    ],
    dependencies: [
        .package(path: "../BLEProtocol"),
        .package(path: "../RideSimulatorKit"),
    ],
    targets: [
        .target(
            name: "BLECentralClient",
            dependencies: [
                "BLEProtocol",
                "RideSimulatorKit",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "BLECentralClientTests",
            dependencies: [
                "BLECentralClient",
                "BLEProtocol",
                "RideSimulatorKit",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
