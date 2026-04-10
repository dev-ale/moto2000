#if DEBUG
import RideSimulatorKit
import SwiftUI

/// Debug-only panel for picking and replaying a scenario.
///
/// Visible only in Debug builds — wrapped in `#if DEBUG` at the top of the
/// file so it cannot leak into Release. Presented as a sheet from
/// ``RootView``.
struct ScenarioPickerView: View {
    @State private var scenarios: [ScenarioDescriptor] = ScenarioCatalog.bundled()
    @State private var selection: ScenarioDescriptor.ID?
    @State private var speed: PlaybackSpeed = .realtime
    @State private var status: String = "Idle"
    @State private var runner: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Scenario") {
                    ForEach(scenarios) { descriptor in
                        Button {
                            selection = descriptor.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(descriptor.name).font(.headline)
                                    Text(descriptor.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection == descriptor.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Playback speed") {
                    Picker("Speed", selection: $speed) {
                        ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Status") {
                    Text(status).font(.footnote).monospaced()
                }

                Section {
                    Button("Play") { play() }
                        .disabled(selection == nil || runner != nil)
                    Button("Stop", role: .destructive) { stop() }
                        .disabled(runner == nil)
                }
            }
            .navigationTitle("Ride Simulator")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func play() {
        guard let id = selection,
              let descriptor = scenarios.first(where: { $0.id == id })
        else {
            return
        }
        status = "Loading…"
        runner = Task {
            do {
                let scenario = try ScenarioLoader.load(from: descriptor.url)
                status = "Playing \(scenario.name) at \(speed.label)"
                let env = SimulatorEnvironment()
                let clock = try WallClock(speedMultiplier: speed.rawValue)
                let player = ScenarioPlayer(environment: env, clock: clock)
                await player.play(scenario)
                status = "Finished \(scenario.name)"
            } catch {
                status = "Error: \(error)"
            }
            runner = nil
        }
    }

    private func stop() {
        runner?.cancel()
        runner = nil
        status = "Stopped"
    }
}

struct ScenarioDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let url: URL
}

enum ScenarioCatalog {
    /// Finds scenario JSON files bundled into the app under
    /// `Fixtures/scenarios/`. The files are copied in by Tuist as
    /// resources so the app can read them at runtime.
    static func bundled() -> [ScenarioDescriptor] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        // Tuist may nest resources under Fixtures/scenarios/ or flatten
        // them into the bundle root. Try the nested path first, then fall
        // back to the bundle root.
        let scenarioDir = resourceURL
            .appendingPathComponent("Fixtures/scenarios", isDirectory: true)
        let nested = (try? FileManager.default.contentsOfDirectory(
            at: scenarioDir, includingPropertiesForKeys: nil)) ?? []
        let items = nested.isEmpty
            ? ((try? FileManager.default.contentsOfDirectory(
                at: resourceURL, includingPropertiesForKeys: nil)) ?? [])
            : nested
        return items
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ScenarioDescriptor? in
                guard let data = try? Data(contentsOf: url),
                      let scenario = try? ScenarioLoader.decode(data)
                else {
                    return nil
                }
                return ScenarioDescriptor(
                    id: scenario.name,
                    name: scenario.name,
                    summary: scenario.summary,
                    url: url
                )
            }
            .sorted { $0.name < $1.name }
    }
}

#Preview {
    ScenarioPickerView()
}
#endif
