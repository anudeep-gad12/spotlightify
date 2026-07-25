import XCTest
@testable import Spotlightify

final class SpotifyModelsTests: XCTestCase {
    func testQueueResponseDecodesTracksAndFiltersEpisodes() throws {
        let json = """
        {
          "currently_playing": \(trackJSON(id: "current", name: "Now Track")),
          "queue": [
            \(trackJSON(id: "next", name: "Next Track")),
            {
              "id": "episode-1",
              "name": "Podcast Episode",
              "type": "episode",
              "uri": "spotify:episode:episode-1"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SpotifyQueueResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.currentlyPlaying?.id, "current")
        XCTAssertEqual(response.queue.map(\.id), ["next"])
    }

    func testRecentlyPlayedResponseDecodesTrackAndPlayedAt() throws {
        let json = """
        {
          "items": [
            {
              "track": \(trackJSON(id: "recent", name: "Recent Track")),
              "played_at": "2026-05-18T10:12:30.123Z"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.items.first?.track.id, "recent")
        XCTAssertNotNil(response.items.first?.playedAt)
    }

    private func trackJSON(id: String, name: String) -> String {
        """
        {
          "id": "\(id)",
          "name": "\(name)",
          "type": "track",
          "uri": "spotify:track:\(id)",
          "duration_ms": 210000,
          "artists": [{ "name": "The Strokes" }],
          "album": {
            "name": "Test Album",
            "images": [
              { "url": "https://example.com/cover.jpg", "width": 300, "height": 300 }
            ]
          }
        }
        """
    }
}
