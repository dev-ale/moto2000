// swift-tools-version: 6.0
import PackageDescription

/// RideSimulatorKit — replay a complete motorcycle ride into the iOS app's
/// data providers without a bike, a GPS, a real IMU, or a BLE peripheral.
///
/// This package defines:
///
/// - Swift protocols for every iOS data source (location, heading, motion,
///   weather, now-playing, calls, calendar) with real and mock implementations.
/// - A scenario file format that describes a ride as a timeline of events.
/// - A deterministic `ScenarioPlayer` that drives the mock providers off a
///   virtual clock, so scenarios replay identically in tests and in the dev UI.
/// - A `ScenarioRecorder` that captures a live run of the real providers into
///   a replayable scenario file.
///
/// The host simulator and loopback BLE transport move to the follow-up package
/// in Slice 1.5b.
let package = Package(
    name: "RideSimulatorKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RideSimulatorKit",
            targets: ["RideSimulatorKit"]
        ),
    ],
    dependencies: [
        .package(path: "../BLEProtocol"),
    ],
    targets: [
        .target(
            name: "RideSimulatorKit",
            dependencies: ["BLEProtocol"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "RideSimulatorKitTests",
            dependencies: ["RideSimulatorKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
