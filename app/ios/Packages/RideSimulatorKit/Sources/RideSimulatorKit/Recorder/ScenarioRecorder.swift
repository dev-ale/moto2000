import Foundation

/// Captures live events from the real providers into a ``Scenario`` that
/// can be replayed later.
///
/// The recorder is stopped explicitly via ``stop()``; at that point it
/// returns the accumulated scenario. Timestamps are measured against the
/// injected clock's `nowSeconds` at the moment each event arrives.
public actor ScenarioRecorder {
    private let clock: any SimulatedClock
    private var name: String
    private var summary: String
    private var locationSamples: [LocationSample] = []
    private var headingSamples: [HeadingSample] = []
    private var motionSamples: [MotionSample] = []
    private var weatherSnapshots: [WeatherSnapshot] = []
    private var nowPlayingSnapshots: [NowPlayingSnapshot] = []
    private var callEvents: [CallEvent] = []
    private var calendarEvents: [CalendarEvent] = []
    private var isRunning = false

    public init(clock: any SimulatedClock, name: String, summary: String = "") {
        self.clock = clock
        self.name = name
        self.summary = summary
    }

    public func start() { isRunning = true }

    public func record(_ sample: LocationSample) async {
        guard isRunning else { return }
        var stamped = sample
        stamped.scenarioTime = await clock.nowSeconds
        locationSamples.append(stamped)
    }

    public func record(_ sample: HeadingSample) async {
        guard isRunning else { return }
        var stamped = sample
        stamped.scenarioTime = await clock.nowSeconds
        headingSamples.append(stamped)
    }

    public func record(_ sample: MotionSample) async {
        guard isRunning else { return }
        var stamped = sample
        stamped.scenarioTime = await clock.nowSeconds
        motionSamples.append(stamped)
    }

    public func record(_ snapshot: WeatherSnapshot) async {
        guard isRunning else { return }
        var stamped = snapshot
        stamped.scenarioTime = await clock.nowSeconds
        weatherSnapshots.append(stamped)
    }

    public func record(_ snapshot: NowPlayingSnapshot) async {
        guard isRunning else { return }
        var stamped = snapshot
        stamped.scenarioTime = await clock.nowSeconds
        nowPlayingSnapshots.append(stamped)
    }

    public func record(_ event: CallEvent) async {
        guard isRunning else { return }
        var stamped = event
        stamped.scenarioTime = await clock.nowSeconds
        callEvents.append(stamped)
    }

    public func record(_ event: CalendarEvent) async {
        guard isRunning else { return }
        var stamped = event
        stamped.scenarioTime = await clock.nowSeconds
        calendarEvents.append(stamped)
    }

    /// Ends recording and returns the captured scenario. Duration is the
    /// clock's current time at the moment ``stop()`` is called.
    public func stop() async -> Scenario {
        isRunning = false
        let duration = await clock.nowSeconds
        return Scenario(
            name: name,
            summary: summary,
            durationSeconds: duration,
            locationSamples: locationSamples,
            headingSamples: headingSamples,
            motionSamples: motionSamples,
            weatherSnapshots: weatherSnapshots,
            nowPlayingSnapshots: nowPlayingSnapshots,
            callEvents: callEvents,
            calendarEvents: calendarEvents
        )
    }
}
