import XCTest

@testable import ScramCore

final class StaticNowPlayingClientTests: XCTestCase {
    func test_returnsStoredResponse() async throws {
        let response = NowPlayingClientResponse(
            title: "Moving On",
            artist: "The Riders",
            album: "Asphalt",
            isPlaying: true,
            positionSeconds: 45,
            durationSeconds: 240
        )
        let client = StaticNowPlayingClient(response: response)
        let fetched = try await client.fetchNowPlaying()
        XCTAssertEqual(fetched, response)
    }

    func test_returnsNilWhenNothingScripted() async throws {
        let client = StaticNowPlayingClient()
        let fetched = try await client.fetchNowPlaying()
        XCTAssertNil(fetched)
    }

    func test_setReplacesStoredResponse() async throws {
        let client = StaticNowPlayingClient()
        client.set(
            NowPlayingClientResponse(
                title: "A",
                artist: "B",
                album: "C",
                isPlaying: false,
                positionSeconds: nil,
                durationSeconds: nil
            )
        )
        let fetched = try await client.fetchNowPlaying()
        XCTAssertEqual(fetched?.title, "A")
        XCTAssertNil(fetched?.positionSeconds)

        client.set(nil)
        let nilled = try await client.fetchNowPlaying()
        XCTAssertNil(nilled)
    }

    func test_mediaPlayerClientAlwaysThrowsNotImplemented() async {
        let client = MediaPlayerNowPlayingClient()
        do {
            _ = try await client.fetchNowPlaying()
            XCTFail("expected notImplemented")
        } catch let error as NowPlayingClientError {
            XCTAssertEqual(error, .notImplemented)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
