// swift-tools-version: 6.0
import PackageDescription

/// scenario-to-video — command-line tool that turns a scenario JSON into an
/// MP4 of the dashboard reacting to the ride, using the host simulator as the
/// renderer and ffmpeg to stitch the frames.
///
/// This is a developer tool, not a CI artefact. It is NOT wired into any
/// GitHub Actions workflow.
let package = Package(
    name: "scenario-to-video",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../app/ios/Packages/BLEProtocol"),
        .package(path: "../../app/ios/Packages/RideSimulatorKit"),
    ],
    targets: [
        .executableTarget(
            name: "ScenarioToVideo",
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
            name: "ScenarioToVideoTests",
            dependencies: ["ScenarioToVideo"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
