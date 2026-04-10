import ProjectDescription

// ScramScreen iOS companion app.
//
// Project layout:
//   Sources/        SwiftUI app shell
//   Tests/          XCTest unit tests for the app shell
//   UITests/        XCUITest UI tests
//   Packages/       Local Swift packages (BLEProtocol, …) added in later slices
//
// The Apple Developer Team ID is read from the environment via `TUIST_DEVELOPMENT_TEAM`.
// Developers set it once in `.env.tuist` (gitignored) — see docs/contributing.md.
let developmentTeam: SettingValue = .string(
    Environment.developmentTeam.getString(default: "")
)

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEVELOPMENT_TEAM": developmentTeam,
    "CODE_SIGN_STYLE": "Automatic",
]

let project = Project(
    name: "ScramScreen",
    organizationName: "moto2000",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "Packages/BLEProtocol"),
        .local(path: "Packages/BLECentralClient"),
        .local(path: "Packages/RideSimulatorKit"),
        .local(path: "Packages/ScramCore"),
    ],
    settings: .settings(
        base: baseSettings,
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "ScramScreen",
            destinations: .iOS,
            product: .app,
            bundleId: "com.alejandro.moto2000.ScramScreen",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleName": "ScramScreen",
                "CFBundleDisplayName": "ScramScreen",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                ],
                "NSBluetoothAlwaysUsageDescription":
                    "ScramScreen uses Bluetooth to send dashboard data to your motorcycle display.",
                "NSLocationWhenInUseUsageDescription":
                    "ScramScreen uses your location to show speed, heading, and navigation on your motorcycle display.",
                "NSLocationAlwaysAndWhenInUseUsageDescription":
                    "ScramScreen continues to read your location during rides so your dashboard stays live in the background.",
                "NSAccessorySetupKitSupports": [
                    "Bluetooth",
                ],
                "NSCalendarsFullAccessUsageDescription":
                    "ScramScreen reads your calendar to show upcoming appointments on your motorcycle display.",
                "ITSAppUsesNonExemptEncryption": false,
                "UIBackgroundModes": [
                    "bluetooth-central",
                    "location",
                ],
            ]),
            sources: ["Sources/**"],
            // Scenario fixtures are bundled into the app so the debug-only
            // ride simulator panel can read them at runtime. The Swift code
            // that references them is wrapped in `#if DEBUG`, so Release
            // builds ship the files but never read them — trivial cost for
            // a simpler Tuist config.
            resources: [
                .glob(pattern: "Sources/Assets.xcassets/**"),
                .glob(pattern: "Fixtures/scenarios/**"),
            ],
            entitlements: .file(path: "ScramScreen.entitlements"),
            dependencies: [
                .package(product: "BLEProtocol"),
                .package(product: "BLECentralClient"),
                .package(product: "RideSimulatorKit"),
                .package(product: "ScramCore"),
            ]
        ),
        .target(
            name: "ScramScreenTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.alejandro.moto2000.ScramScreenTests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "ScramScreen"),
            ]
        ),
        .target(
            name: "ScramScreenUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.alejandro.moto2000.ScramScreenUITests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "ScramScreen"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "ScramScreen",
            shared: true,
            buildAction: .buildAction(targets: ["ScramScreen"]),
            testAction: .targets(
                [
                    .testableTarget(target: "ScramScreenTests"),
                    .testableTarget(target: "ScramScreenUITests"),
                ],
                configuration: "Debug",
                options: .options(coverage: true, codeCoverageTargets: ["ScramScreen"])
            ),
            runAction: .runAction(configuration: "Debug", executable: "ScramScreen")
        ),
    ]
)
