import Foundation

public struct NowPlayingSnapshot: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var positionSeconds: Double
    public var durationSeconds: Double

    public init(
        scenarioTime: Double,
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        positionSeconds: Double,
        durationSeconds: Double
    ) {
        self.scenarioTime = scenarioTime
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }
}

public protocol NowPlayingProvider: Sendable {
    var snapshots: AsyncStream<NowPlayingSnapshot> { get }
    func start() async
    func stop() async
}
