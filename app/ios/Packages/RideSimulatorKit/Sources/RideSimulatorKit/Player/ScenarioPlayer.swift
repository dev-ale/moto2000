import Foundation

/// Drives a ``SimulatorEnvironment`` by replaying a ``Scenario`` against a
/// ``SimulatedClock``.
///
/// The player merges every kind of sample into one time-sorted timeline
/// and sleeps the clock until each one. Tests pass in a ``VirtualClock``
/// and assert on what the mock providers emit; the dev-build UI passes in
/// a ``WallClock`` configured by ``PlaybackSpeed``.
///
/// `play(_:)` runs until the scenario is exhausted or the enclosing task
/// is cancelled.
public actor ScenarioPlayer {
    public enum State: Equatable, Sendable {
        case idle
        case playing
        case finished
        case cancelled
    }

    private let environment: SimulatorEnvironment
    private let clock: any SimulatedClock
    private var currentState: State = .idle

    public init(environment: SimulatorEnvironment, clock: any SimulatedClock) {
        self.environment = environment
        self.clock = clock
    }

    public var state: State { currentState }

    /// Replays every event in `scenario`, sleeping on the clock until each
    /// one's timestamp and emitting into the matching mock provider.
    /// Returns when the last event has been emitted or when the enclosing
    /// task is cancelled.
    public func play(_ scenario: Scenario) async {
        currentState = .playing
        let steps = makeSteps(scenario)
        for step in steps {
            if Task.isCancelled {
                currentState = .cancelled
                return
            }
            do {
                try await clock.sleep(until: step.time)
            } catch {
                currentState = .cancelled
                return
            }
            step.emit(environment)
        }
        currentState = .finished
    }

    // MARK: - Timeline merging

    struct Step: Sendable {
        let time: Double
        let emit: @Sendable (SimulatorEnvironment) -> Void
    }

    func makeSteps(_ scenario: Scenario) -> [Step] {
        var steps: [Step] = []
        steps.reserveCapacity(
            scenario.locationSamples.count
                + scenario.headingSamples.count
                + scenario.motionSamples.count
                + scenario.weatherSnapshots.count
                + scenario.nowPlayingSnapshots.count
                + scenario.callEvents.count
                + scenario.calendarEvents.count
        )
        for sample in scenario.locationSamples {
            steps.append(Step(time: sample.scenarioTime) { env in env.location.emit(sample) })
        }
        for sample in scenario.headingSamples {
            steps.append(Step(time: sample.scenarioTime) { env in env.heading.emit(sample) })
        }
        for sample in scenario.motionSamples {
            steps.append(Step(time: sample.scenarioTime) { env in env.motion.emit(sample) })
        }
        for snapshot in scenario.weatherSnapshots {
            steps.append(Step(time: snapshot.scenarioTime) { env in env.weather.emit(snapshot) })
        }
        for snapshot in scenario.nowPlayingSnapshots {
            steps.append(Step(time: snapshot.scenarioTime) { env in env.nowPlaying.emit(snapshot) })
        }
        for event in scenario.callEvents {
            steps.append(Step(time: event.scenarioTime) { env in env.calls.emit(event) })
        }
        for event in scenario.calendarEvents {
            steps.append(Step(time: event.scenarioTime) { env in env.calendar.emit(event) })
        }
        steps.sort { $0.time < $1.time }
        return steps
    }
}
