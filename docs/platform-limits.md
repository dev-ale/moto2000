# Platform limits

Notes on iOS restrictions that affect ScramScreen's design, and the follow-up
work each one implies.

## Now Playing info (`MPNowPlayingInfoCenter`) — Slice 8

**Restriction.** `MPNowPlayingInfoCenter.default().nowPlayingInfo` is
process-local. Reads only return the data the current app itself has published
via that API. Third-party audio players — Spotify, YouTube Music, Pocket Casts,
etc. — do not expose their metadata through it from any other process. There is
no public iOS API that lets an arbitrary app read "what is playing right now"
across the device.

**What Slice 8 ships.** The `NowPlayingClient` protocol in
`app/ios/Packages/ScramCore/Sources/ScramCore/Music/` defines an abstract
"where does the current playing info come from" seam. The domain consumes it
through `RealNowPlayingProvider`, which polls a client on a `SimulatedClock`
and republishes snapshots to `MusicService`. Tests run against
`StaticNowPlayingClient` + `VirtualClock` and never touch a system framework.

A `MediaPlayerNowPlayingClient` stub exists and is gated on
`#if canImport(MediaPlayer) && os(iOS)`. It currently always throws
`NowPlayingClientError.notImplemented` — see the block comment at the top of
`MediaPlayerNowPlayingClient.swift` for the full rationale.

**What a follow-up slice needs to decide.** There are three realistic options
for wiring real data:

1. **Make ScramScreen itself the Now Playing source.** We would play audio
   from our own process and publish to `MPNowPlayingInfoCenter`. Wrong shape
   for a motorcycle dashboard — rejected.
2. **Use `MPMusicPlayerController.systemMusicPlayer`.** This reads the Apple
   Music app's queue/state. It only works for tracks played through Apple
   Music (never Spotify) and requires an `NSAppleMusicUsageDescription` Info.plist
   entry and user consent on first use. Acceptable for the "I use Apple Music"
   user; the BLE payload would ship Apple-Music-only metadata.
3. **Private-API bridge.** Off limits for App Store submission — not pursued.

The follow-up slice picks option (2), updates the stub to fetch the
`nowPlayingItem` on each poll, and adds a permission-gated prompt to the UI.

**What the user sees today.** The music screen renders correctly in the host
simulator against fixture data, and integration tests prove the whole iOS
pipeline (scenario snapshots → `MusicService` → BLE payload) works
end-to-end using the simulator's scripted `NowPlayingSnapshot` values. Running
the app against a real iPhone produces no music payloads until the follow-up
slice lands; the dashboard simply falls back to the last-known stale payload
(or hides the screen if none has been seen) via the Slice 17 staleness cache.
