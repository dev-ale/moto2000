// swift-tools-version: 6.0
import PackageDescription

/// ScramCore — the domain layer shared by the ScramScreen iOS app targets.
///
/// This package owns the thin wrappers over iOS system frameworks
/// (CoreLocation, CoreMotion, EventKit, …) behind injectable protocols and
/// the per-screen services that transform raw samples into BLEProtocol
/// payloads. It depends on BLEProtocol for wire encoding and on
/// RideSimulatorKit for the provider protocol definitions (``LocationProvider``
/// et al.) so tests can run against the same mocks the simulator uses.
///
/// Slice 3 brings in the first real provider (``RealLocationProvider``) and
/// the first screen service (``SpeedHeadingService``).
let package = Package(
    name: "ScramCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ScramCore",
            targets: ["ScramCore"]
        ),
    ],
    dependencies: [
        .package(path: "../BLEProtocol"),
        .package(path: "../RideSimulatorKit"),
    ],
    targets: [
        .target(
            name: "ScramCore",
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
            name: "ScramCoreTests",
            dependencies: [
                "ScramCore",
                "BLEProtocol",
                "RideSimulatorKit",
            ],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
