import Foundation

// Real CLI lives in `ScenarioToVideoCLI.run`; this file is the entry point
// that calls it. Keeping `main.swift` minimal makes the logic unit-testable
// (it lives in plain structs, not a `@main` type).
do {
    try ScenarioToVideoCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CLIError {
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(error.exitCode)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
