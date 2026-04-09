import ProjectDescription

// Tuist workspace configuration for the ScramScreen iOS app.
// Tuist version: pinned in `.tuist-version` at the repo root.
let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: .upToNextMajor("16.0"),
        swiftVersion: "6.0"
    )
)
