import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class MusicServiceTests: XCTestCase {
    func test_encodePayload_playingTrack() async throws {
        let mock = MockNowPlayingProvider()
        let service = MusicService(provider: mock)
        service.start()

        mock.emit(
            NowPlayingSnapshot(
                scenarioTime: 0,
                title: "Moving On",
                artist: "The Riders",
                album: "Asphalt",
                isPlaying: true,
                positionSeconds: 45,
                durationSeconds: 240
            )
        )

        var iterator = service.encodedPayloads.makeAsyncIterator()
        let next = await iterator.next(); let blob = try XCTUnwrap(next)
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .music(let music, _) = payload else {
            XCTFail("expected music payload, got \(payload)")
            return
        }
        XCTAssertEqual(music.title, "Moving On")
        XCTAssertEqual(music.artist, "The Riders")
        XCTAssertEqual(music.album, "Asphalt")
        XCTAssertEqual(music.positionSeconds, 45)
        XCTAssertEqual(music.durationSeconds, 240)
        XCTAssertTrue(music.isPlaying)

        service.stop()
    }

    func test_encodePayload_pausedTrack() async throws {
        let mock = MockNowPlayingProvider()
        let service = MusicService(provider: mock)
        service.start()

        mock.emit(
            NowPlayingSnapshot(
                scenarioTime: 0,
                title: "Midnight Sun",
                artist: "Solo Project",
                album: "Demo",
                isPlaying: false,
                positionSeconds: 120,
                durationSeconds: 180
            )
        )

        var iterator = service.encodedPayloads.makeAsyncIterator()
        let next = await iterator.next(); let blob = try XCTUnwrap(next)
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .music(let music, _) = payload else {
            XCTFail("expected music payload")
            return
        }
        XCTAssertFalse(music.isPlaying)

        service.stop()
    }

    func test_encodePayload_unknownPositionAndDuration() async throws {
        let mock = MockNowPlayingProvider()
        let service = MusicService(provider: mock)
        service.start()

        mock.emit(
            NowPlayingSnapshot(
                scenarioTime: 0,
                title: "Radio Stream",
                artist: "Live DJ",
                album: "Broadcast",
                isPlaying: true,
                positionSeconds: -1,  // unknown sentinel
                durationSeconds: -1   // unknown sentinel
            )
        )

        var iterator = service.encodedPayloads.makeAsyncIterator()
        let next = await iterator.next(); let blob = try XCTUnwrap(next)
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .music(let music, _) = payload else {
            XCTFail("expected music payload")
            return
        }
        XCTAssertEqual(music.positionSeconds, MusicData.unknownU16)
        XCTAssertEqual(music.durationSeconds, MusicData.unknownU16)

        service.stop()
    }

    func test_encodePayload_truncatesLongStrings() async throws {
        let mock = MockNowPlayingProvider()
        let service = MusicService(provider: mock)
        service.start()

        // Title is way too long; service must truncate to fit 31 bytes.
        mock.emit(
            NowPlayingSnapshot(
                scenarioTime: 0,
                title: String(repeating: "A", count: 200),
                artist: String(repeating: "B", count: 200),
                album: String(repeating: "C", count: 200),
                isPlaying: true,
                positionSeconds: 0,
                durationSeconds: 0
            )
        )

        var iterator = service.encodedPayloads.makeAsyncIterator()
        let next = await iterator.next(); let blob = try XCTUnwrap(next)
        let payload = try ScreenPayloadCodec.decode(blob)
        guard case .music(let music, _) = payload else {
            XCTFail("expected music payload")
            return
        }
        XCTAssertEqual(music.title.count, 31)  // 31 bytes, room for terminator
        XCTAssertEqual(music.artist.count, 23)
        XCTAssertEqual(music.album.count, 23)
        XCTAssertEqual(music.title, String(repeating: "A", count: 31))

        service.stop()
    }

    func test_packSeconds_unknownMapsToSentinel() {
        XCTAssertEqual(MusicService.packSeconds(-1), MusicData.unknownU16)
        XCTAssertEqual(MusicService.packSeconds(-0.0001), MusicData.unknownU16)
        XCTAssertEqual(MusicService.packSeconds(.nan), MusicData.unknownU16)
    }

    func test_packSeconds_clampsBelowSentinel() {
        XCTAssertEqual(MusicService.packSeconds(0), 0)
        XCTAssertEqual(MusicService.packSeconds(45.4), 45)
        XCTAssertEqual(MusicService.packSeconds(45.6), 46)
        XCTAssertEqual(MusicService.packSeconds(100_000), 65534)
        XCTAssertEqual(MusicService.packSeconds(65535), 65534)
    }

    func test_truncateUTF8_respectsMultiByteBoundaries() {
        // Each 'é' is 2 bytes.
        let input = String(repeating: "é", count: 20)
        // maxByteCount=5 → only 2 full 'é' (4 bytes) fit; the 3rd scalar would push to 6.
        let out = MusicService.truncateUTF8(input, maxByteCount: 5)
        XCTAssertEqual(out, "éé")
        XCTAssertEqual(out.utf8.count, 4)
    }

    func test_truncateUTF8_passthroughWhenShort() {
        XCTAssertEqual(MusicService.truncateUTF8("abc", maxByteCount: 10), "abc")
    }
}
