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

    @MainActor
    func testHorizontalArrowsSwitchColumnsWithoutOpeningAlbum() {
        let model = makeViewModel()
        model.applySearchResults(
            tracks: (0..<3).map { makeTrack(id: "song-\($0)", name: "Song") },
            albums: (0..<3).map { makeAlbum(id: "album-\($0)") }
        )
        model.select(index: 1)

        XCTAssertTrue(model.canNavigateIntoAlbum)
        model.navigateIntoAlbum()
        XCTAssertEqual(model.selectedIndex, 4)
        XCTAssertNil(model.selectedAlbum)
        XCTAssertTrue(model.canNavigateBackFromAlbum)

        model.navigateBackFromAlbum()
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertFalse(model.canNavigateBackFromAlbum)
    }

    @MainActor
    func testVerticalArrowsStayWithinEachColumn() {
        let model = makeViewModel()
        model.applySearchResults(
            tracks: (0..<2).map { makeTrack(id: "song-\($0)", name: "Song") },
            albums: (0..<3).map { makeAlbum(id: "album-\($0)") }
        )
        model.moveSelection(by: 20)
        XCTAssertEqual(model.selectedIndex, 1)
        model.navigateIntoAlbum()
        XCTAssertEqual(model.selectedIndex, 3)
        model.moveSelection(by: -20)
        XCTAssertEqual(model.selectedIndex, 2)
        model.moveSelection(by: 20)
        XCTAssertEqual(model.selectedIndex, 4)
        model.navigateBackFromAlbum()
        XCTAssertEqual(model.selectedIndex, 1)
    }

    @MainActor
    func testHorizontalNavigationClampsToShorterAlbumColumn() {
        let model = makeViewModel()
        model.applySearchResults(
            tracks: (0..<4).map { makeTrack(id: "song-\($0)", name: "Song") },
            albums: [makeAlbum(id: "only-album")]
        )
        model.select(index: 3)
        model.navigateIntoAlbum()
        XCTAssertEqual(model.selectedIndex, 4)
        XCTAssertNil(model.selectedAlbum)
    }

    @MainActor
    func testEmptyColumnsDoNotReceiveSelection() {
        let model = makeViewModel()
        model.applySearchResults(tracks: [makeTrack(id: "song", name: "Song")], albums: [])
        XCTAssertFalse(model.canNavigateIntoAlbum)
        model.navigateIntoAlbum()
        XCTAssertEqual(model.selectedIndex, 0)

        model.applySearchResults(tracks: [], albums: [makeAlbum(id: "only-album")])
        XCTAssertFalse(model.canNavigateBackFromAlbum)
        model.navigateBackFromAlbum()
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedIndex, 0)

        model.applySearchResults(tracks: [], albums: [])
        XCTAssertFalse(model.canNavigateIntoAlbum)
        XCTAssertFalse(model.canNavigateBackFromAlbum)
        XCTAssertFalse(model.canMoveSelection)
    }

    @MainActor
    private func makeViewModel() -> SearchViewModel {
        let configuration = AppConfiguration(bundledSpotifyClientID: "test", callbackScheme: "spotlightify")
        let authManager = SpotifyAuthManager(
            configuration: configuration,
            keychain: KeychainStore(service: "search-navigation-tests"),
            clientIDProvider: { "test" },
            session: .shared
        )
        return SearchViewModel(
            apiClient: SpotifyAPIClient(authManager: authManager),
            redirectURI: "spotlightify://callback"
        )
    }

    private func makeAlbum(id: String) -> SpotifyAlbumItem {
        SpotifyAlbumItem(
            id: id, name: "Album", artists: [], images: [],
            uri: "spotify:album:\(id)", albumType: "album", totalTracks: 10
        )
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
