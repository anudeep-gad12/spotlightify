import XCTest
@testable import Spotlightify

final class SearchViewModelTests: XCTestCase {
    func testQueueDeduplicationRemovesCurrentTrackAndRepeatedUpcomingTracks() {
        let current = makeTrack(id: "current", name: "Current")
        let next = makeTrack(id: "next", name: "Next")
        let later = makeTrack(id: "later", name: "Later")

        let tracks = [current, current, next, next, current, later, later]

        let deduplicated = SearchViewModel.deduplicatedQueueTracks(
            tracks,
            excludingCurrentTrackID: current.id
        )

        XCTAssertEqual(deduplicated.map(\.id), ["next", "later"])
    }

    private func makeTrack(id: String, name: String) -> SpotifyTrack {
        let json = """
        {
          "id": "\(id)",
          "name": "\(name)",
          "type": "track",
          "uri": "spotify:track:\(id)",
          "duration_ms": 180000,
          "artists": [{ "name": "Artist" }],
          "album": {
            "name": "Album",
            "images": []
          }
        }
        """
        return try! JSONDecoder().decode(SpotifyTrack.self, from: Data(json.utf8))
    }
}
