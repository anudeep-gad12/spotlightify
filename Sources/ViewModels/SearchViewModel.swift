import Foundation

enum NowPlayingState: Equatable {
    case hidden
    case loading
    case showing(NowPlayingSummary)
}

struct NowPlayingSummary: Equatable {
    let title: String
    let artistLine: String
    let artworkURL: URL?
    let isPlaying: Bool
    let deviceName: String?
    let progressMs: Int?
    let durationMs: Int?
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            if !query.isEmpty {
                activeMode = .search
                clearMessage()
            }
            startDebouncedSearch(for: query)
        }
    }
    @Published private(set) var activeMode: SearchPanelMode = .search
    @Published private(set) var selectedIndex = 0
    @Published private(set) var focusMode: SearchFocusMode = .mainList
    @Published private(set) var albumTrackSelectedIndex = 0
    @Published private(set) var panelState: SearchPanelState = .helper
    @Published private(set) var recentState: TrackCollectionState = .idle
    @Published private(set) var queueState: TrackCollectionState = .idle
    @Published private(set) var inlineMessage: String?
    @Published private(set) var inlineMessageIsError = false
    @Published private(set) var inlineMessageIsLoading = false
    @Published private(set) var loginInProgress = false
    @Published private(set) var focusRequestID = UUID()
    @Published private(set) var nowPlayingState: NowPlayingState = .hidden
    @Published private(set) var nowPlayingRefreshInProgress = false
    @Published var setupClientID = ""
    @Published var hasSavedClientID = false

    var onPlayRequested: ((SpotifyTrack) async -> Void)?
    var onQueueRequested: ((SpotifyTrack) async -> Void)?
    var onSeekRequested: ((Int) async -> Void)?
    var onLoginRequested: (() -> Void)?
    var onSaveClientIDRequested: ((String) -> Void)?
    var onClearConfigurationRequested: (() -> Void)?
    var onOpenSpotifyRequested: (() -> Void)?
    var isSpotifyConfigured: (() -> Bool)?
    var currentConfiguredClientID: (() -> String)?

    private let apiClient: SpotifyAPIClient
    let redirectURI: String
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var nowPlayingTask: Task<Void, Never>?
    private var nowPlayingRefreshID = UUID()
    private var recentTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var pendingSelectionOffset = 0
    @Published private(set) var selectedAlbum: SpotifyAlbumItem?
    @Published private(set) var albumTracksState: TrackCollectionState = .idle
    private var currentResults: [SearchResultRow] = []
    private let debounceDelayMs: UInt64 = 400

    init(apiClient: SpotifyAPIClient, redirectURI: String) {
        self.apiClient = apiClient
        self.redirectURI = redirectURI
    }

    var canMoveSelection: Bool {
        switch focusMode {
        case .mainList:
            return !activeItems.isEmpty
        case .albumDetail:
            if case .loaded(let items) = albumTracksState { return !items.isEmpty }
            return false
        }
    }

    var canHandleSelectionMovement: Bool {
        canMoveSelection || activeCollectionIsLoading
    }

    var canNavigateIntoAlbum: Bool {
        guard activeMode == .search, case .results = panelState else { return false }
        return focusMode == .mainList && !searchAlbumItems.isEmpty
    }

    var canNavigateBackFromAlbum: Bool {
        focusMode == .albumDetail || (selectedRowAlbum != nil && !searchTrackItems.isEmpty)
    }

    var canSwitchModes: Bool {
        switch panelState {
        case .setupRequired, .authenticationRequired:
            return false
        default:
            return true
        }
    }

    var searchItems: [TrackListItem] {
        currentResults.map { row in
            switch row {
            case .track(let track):
                return TrackListItem(track: track)
            case .album(let album):
                return TrackListItem(
                    id: "album-\(album.id)",
                    track: SpotifyTrack(
                        id: album.id,
                        name: album.name,
                        artists: album.artists,
                        album: SpotifyAlbum(name: album.name, images: album.images),
                        uri: album.uri,
                        durationMs: nil
                    ),
                    metadata: "Album · \(album.totalTracks ?? 0) tracks"
                )
            }
        }
    }

    var searchTrackItems: [TrackListItem] {
        searchItems.filter { !$0.id.hasPrefix("album-") }
    }

    var searchAlbumItems: [TrackListItem] {
        searchItems.filter { $0.id.hasPrefix("album-") }
    }

    func applySearchResults(tracks: [SpotifyTrack], albums: [SpotifyAlbumItem]) {
        let rows = tracks.map(SearchResultRow.track) + albums.map(SearchResultRow.album)
        currentResults = rows
        closeAlbumDetail()
        // Pending vertical movement belongs to the initial nonempty column.
        selectedIndex = consumePendingSelectionIndex(itemCount: tracks.isEmpty ? albums.count : tracks.count)
        panelState = rows.isEmpty ? .empty : .results(rows)
    }

    func prepareForPresentation() {
        clearMessage()
        searchTask?.cancel()
        nowPlayingTask?.cancel()
        recentTask?.cancel()
        queueTask?.cancel()
        recentState = .idle
        queueState = .idle

        guard isSpotifyConfigured?() != false else {
            nowPlayingState = .hidden
            presentSetup(clientID: currentConfiguredClientID?() ?? "", hasSavedClientID: hasSavedClientID)
            return
        }

        Task {
            let authorizationState = await apiClient.authorizationStateForSearch()

            switch authorizationState {
            case .requiresInteractiveLogin:
                currentResults = []
                selectedIndex = 0
                nowPlayingState = .hidden
                panelState = .authenticationRequired("Sign in to Spotify to search.")
            case .interactiveLoginInProgress:
                currentResults = []
                selectedIndex = 0
                nowPlayingState = .hidden
                panelState = .authenticationRequired("Finish Spotify login in the browser.")
            case .ready:
                refreshNowPlaying()
                switch activeMode {
                case .search:
                    if query.isEmpty {
                        currentResults = []
                        selectedIndex = 0
                        panelState = .helper
                    } else {
                        performSearch(for: query)
                    }
                case .recent:
                    fetchRecentTracks(force: true)
                case .queue:
                    fetchQueue(force: true)
                }
            }
        }
    }

    func setMode(_ mode: SearchPanelMode) {
        guard activeMode != mode else { return }
        closeAlbumDetail()
        activeMode = mode
        selectedIndex = 0
        pendingSelectionOffset = 0
        clearMessage()

        switch mode {
        case .search:
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentResults = []
                panelState = isSpotifyConfigured?() == false ? .setupRequired : .helper
            } else {
                performSearch(for: query)
            }
        case .recent:
            fetchRecentTracks(force: false)
        case .queue:
            fetchQueue(force: false)
        }
    }

    func cycleMode(backwards: Bool = false) {
        let modes = SearchPanelMode.allCases
        guard let currentIndex = modes.firstIndex(of: activeMode) else {
            setMode(.search)
            return
        }

        let nextIndex: Int
        if backwards {
            nextIndex = currentIndex == modes.startIndex ? modes.index(before: modes.endIndex) : modes.index(before: currentIndex)
        } else {
            nextIndex = modes.index(after: currentIndex) == modes.endIndex ? modes.startIndex : modes.index(after: currentIndex)
        }
        setMode(modes[nextIndex])
    }

    func setInlineMessage(_ message: String, isError: Bool = true, isLoading: Bool = false) {
        inlineMessage = message
        inlineMessageIsError = isError
        inlineMessageIsLoading = isLoading && !isError
    }

    func moveSelection(by offset: Int) {
        switch focusMode {
        case .mainList:
            let count = activeItems.count
            guard count > 0 else {
                if activeCollectionIsLoading {
                    pendingSelectionOffset = max(0, pendingSelectionOffset + offset)
                }
                return
            }
            if activeMode == .search {
                let songCount = searchTrackItems.count
                let lowerBound = selectedRowAlbum == nil ? 0 : songCount
                let upperBound = selectedRowAlbum == nil ? songCount - 1 : count - 1
                selectedIndex = max(lowerBound, min(upperBound, selectedIndex + offset))
            } else {
                selectedIndex = max(0, min(count - 1, selectedIndex + offset))
            }
        case .albumDetail:
            guard case .loaded(let items) = albumTracksState, !items.isEmpty else {
                if activeCollectionIsLoading {
                    pendingSelectionOffset = max(0, pendingSelectionOffset + offset)
                }
                return
            }
            albumTrackSelectedIndex = max(0, min(items.count - 1, albumTrackSelectedIndex + offset))
        }
    }

    func select(index: Int) {
        guard activeItems.indices.contains(index) else { return }
        selectedIndex = index
        focusMode = .mainList
    }

    func navigateIntoAlbum() {
        guard canNavigateIntoAlbum else { return }
        if let album = selectedRowAlbum {
            openAlbumDetail(album)
        } else if selectedAlbum != nil {
            // Returning from the songs column keeps the open album and its position.
            focusMode = .albumDetail
        } else {
            selectedIndex = searchTrackItems.count + min(selectedIndex, searchAlbumItems.count - 1)
        }
    }

    func navigateBackFromAlbum() {
        if focusMode == .albumDetail {
            let albumID = selectedAlbum?.id
            closeAlbumDetail()
            if let index = searchAlbumItems.firstIndex(where: { $0.track.id == albumID }) {
                selectedIndex = searchTrackItems.count + index
            }
        } else if selectedRowAlbum != nil, !searchTrackItems.isEmpty {
            selectedIndex = min(selectedIndex - searchTrackItems.count, searchTrackItems.count - 1)
        }
    }

    func playSelected() {
        switch focusMode {
        case .mainList:
            if let album = selectedRowAlbum {
                openAlbumDetail(album)
                return
            }
            guard let track = selectedTrack else { return }
            Task { await onPlayRequested?(track) }
        case .albumDetail:
            guard case .loaded(let items) = albumTracksState,
                  items.indices.contains(albumTrackSelectedIndex) else { return }
            Task { await onPlayRequested?(items[albumTrackSelectedIndex].track) }
        }
    }

    func queueSelected() {
        switch focusMode {
        case .mainList:
            if selectedRowAlbum != nil {
                openAlbumDetail(selectedRowAlbum!)
                return
            }
            guard let track = selectedTrack else { return }
            Task { await onQueueRequested?(track) }
        case .albumDetail:
            guard case .loaded(let items) = albumTracksState,
                  items.indices.contains(albumTrackSelectedIndex) else { return }
            Task { await onQueueRequested?(items[albumTrackSelectedIndex].track) }
        }
    }

    func closeAlbumDetail() {
        selectedAlbum = nil
        albumTracksState = .idle
        albumTrackSelectedIndex = 0
        focusMode = .mainList
    }

    private var selectedRowAlbum: SpotifyAlbumItem? {
        guard activeMode == .search,
              case .results = panelState,
              activeItems.indices.contains(selectedIndex) else { return nil }
        let itemID = activeItems[selectedIndex].id
        guard itemID.hasPrefix("album-") else { return nil }
        let albumID = String(itemID.dropFirst(6))
        for row in currentResults {
            if case .album(let album) = row, album.id == albumID {
                return album
            }
        }
        return nil
    }

    private func openAlbumDetail(_ album: SpotifyAlbumItem) {
        if selectedAlbum?.id == album.id {
            closeAlbumDetail()
            return
        }
        selectedAlbum = album
        albumTracksState = .loading
        albumTrackSelectedIndex = 0
        pendingSelectionOffset = 0
        focusMode = .albumDetail

        Task {
            do {
                let albumTracks = try await apiClient.albumTracks(albumID: album.id)
                guard !Task.isCancelled, selectedAlbum?.id == album.id else { return }

                let albumInfo = SpotifyAlbum(name: album.name, images: album.images)
                let items = albumTracks.map { item in
                    let track = SpotifyTrack(
                        id: item.id,
                        name: item.name,
                        artists: item.artists,
                        album: albumInfo,
                        uri: item.uri,
                        durationMs: item.durationMs
                    )
                    return TrackListItem(track: track)
                }
                albumTracksState = items.isEmpty ? .empty : .loaded(items)
                albumTrackSelectedIndex = consumePendingSelectionIndex(itemCount: items.count)
            } catch {
                guard !Task.isCancelled, selectedAlbum?.id == album.id else { return }
                albumTracksState = .error(error.localizedDescription)
            }
        }
    }

    func requestLogin() {
        guard !loginInProgress else { return }
        onLoginRequested?()
    }

    func requestOpenSpotify() {
        onOpenSpotifyRequested?()
    }

    func requestSeek(to positionMS: Int) {
        Task {
            await onSeekRequested?(max(0, positionMS))
        }
    }

    func retrySearchIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        performSearch(for: query)
    }

    func setLoginInProgress(_ inProgress: Bool) {
        loginInProgress = inProgress
    }

    func presentSetup(clientID: String, hasSavedClientID: Bool) {
        searchTask?.cancel()
        recentTask?.cancel()
        queueTask?.cancel()
        activeMode = .search
        currentResults = []
        recentState = .idle
        queueState = .idle
        selectedIndex = 0
        pendingSelectionOffset = 0
        nowPlayingState = .hidden
        setupClientID = clientID
        self.hasSavedClientID = hasSavedClientID
        panelState = .setupRequired
        requestSearchFocus()
    }

    func saveClientID() {
        onSaveClientIDRequested?(setupClientID)
    }

    func clearConfiguration() {
        onClearConfigurationRequested?()
    }

    func requestSearchFocus() {
        focusRequestID = UUID()
    }

    func clearMessage() {
        inlineMessage = nil
        inlineMessageIsError = false
        inlineMessageIsLoading = false
    }

    func clearQuery() {
        query = ""
    }

    func refreshNowPlaying() {
        nowPlayingTask?.cancel()
        let refreshID = UUID()
        nowPlayingRefreshID = refreshID

        guard canShowNowPlaying else {
            nowPlayingState = .hidden
            nowPlayingRefreshInProgress = false
            return
        }

        let isPreservingCurrentContent: Bool
        if case .showing = nowPlayingState {
            isPreservingCurrentContent = true
            nowPlayingRefreshInProgress = true
        } else {
            isPreservingCurrentContent = false
            nowPlayingState = .loading
            nowPlayingRefreshInProgress = false
        }

        nowPlayingTask = Task {
            defer {
                if nowPlayingRefreshID == refreshID {
                    nowPlayingRefreshInProgress = false
                }
            }

            do {
                let playbackState = try await apiClient.currentPlaybackState()
                guard !Task.isCancelled else { return }
                guard let summary = Self.makeNowPlayingSummary(from: playbackState) else {
                    nowPlayingState = .hidden
                    return
                }
                nowPlayingState = .showing(summary)
            } catch {
                guard !Task.isCancelled else { return }
                if !isPreservingCurrentContent {
                    nowPlayingState = .hidden
                }
            }
        }
    }

    func refreshQueueAfterPlaybackChange() {
        if activeMode == .queue || queueState.hasLoadedContent {
            fetchQueue(force: true)
        }
    }

    func clearNowPlaying() {
        nowPlayingTask?.cancel()
        nowPlayingRefreshID = UUID()
        nowPlayingRefreshInProgress = false
        nowPlayingState = .hidden
    }
}

extension SearchViewModel {
    private var selectedTrack: SpotifyTrack? {
        guard activeItems.indices.contains(selectedIndex) else { return nil }
        let item = activeItems[selectedIndex]
        // Album rows are handled by playSelected/queueSelected separately
        if item.id.hasPrefix("album-") {
            return nil
        }
        return item.track
    }

    private var activeItems: [TrackListItem] {
        switch activeMode {
        case .search:
            if case .results = panelState { return searchItems }
            return []
        case .recent:
            if case .loaded(let items) = recentState { return items }
            return []
        case .queue:
            if case .loaded(let items) = queueState { return items }
            return []
        }
    }

    private var activeCollectionIsLoading: Bool {
        switch focusMode {
        case .albumDetail:
            if case .loading = albumTracksState { return true }
            return false
        case .mainList:
            switch activeMode {
            case .search:
                if case .loading = panelState { return true }
            case .recent:
                if case .loading = recentState { return true }
            case .queue:
                if case .loading = queueState { return true }
            }
            return false
        }
    }

    private func consumePendingSelectionIndex(itemCount: Int) -> Int {
        defer { pendingSelectionOffset = 0 }
        guard itemCount > 0 else { return 0 }
        return min(itemCount - 1, pendingSelectionOffset)
    }

    private func startDebouncedSearch(for query: String) {
        debounceTask?.cancel()
        searchTask?.cancel()

        closeAlbumDetail()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            currentResults = []
            pendingSelectionOffset = 0
            if activeMode == .search {
                selectedIndex = 0
                panelState = isSpotifyConfigured?() == false ? .setupRequired : .helper
            }
            return
        }

        currentResults = []
        selectedAlbum = nil
        albumTracksState = .idle
        focusMode = .mainList
        selectedIndex = 0
        pendingSelectionOffset = 0
        if isSpotifyConfigured?() != false {
            panelState = .loading
        }

        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(debounceDelayMs))
                guard !Task.isCancelled else { return }
                performSearch(for: trimmedQuery)
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    private func performSearch(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            currentResults = []
            if activeMode == .search {
                selectedIndex = 0
                panelState = isSpotifyConfigured?() == false ? .setupRequired : .helper
            }
            return
        }

        searchTask = Task {
            guard self.isSpotifyConfigured?() != false else {
                self.presentSetup(clientID: self.currentConfiguredClientID?() ?? "", hasSavedClientID: self.hasSavedClientID)
                return
            }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let authorizationState = await apiClient.authorizationStateForSearch()
            guard !Task.isCancelled else { return }

            switch authorizationState {
            case .requiresInteractiveLogin:
                currentResults = []
                nowPlayingState = .hidden
                panelState = .authenticationRequired("Sign in to Spotify to search.")
                return
            case .interactiveLoginInProgress:
                currentResults = []
                nowPlayingState = .hidden
                panelState = .authenticationRequired("Finish Spotify login in the browser.")
                return
            case .ready:
                panelState = .loading
            }

            do {
                let (tracks, albums) = try await apiClient.searchTracksAndAlbums(query: trimmedQuery)
                guard !Task.isCancelled else { return }
                applySearchResults(tracks: tracks, albums: albums)
            } catch {
                guard !Task.isCancelled else { return }
                currentResults = []
                panelState = .error(error.localizedDescription)
            }
        }
    }

    private func fetchRecentTracks(force: Bool) {
        guard isSpotifyConfigured?() != false else {
            presentSetup(clientID: currentConfiguredClientID?() ?? "", hasSavedClientID: hasSavedClientID)
            return
        }
        if !force, recentState.shouldSkipFetch { return }

        recentTask?.cancel()
        recentState = .loading
        selectedIndex = 0
        pendingSelectionOffset = 0
        recentTask = Task {
            do {
                let items = try await apiClient.recentlyPlayedTracks(limit: 20)
                guard !Task.isCancelled else { return }
                let rows = items.map { item in
                    TrackListItem(
                        id: "recent-\(item.playedAt?.timeIntervalSince1970 ?? 0)-\(item.track.id)",
                        track: item.track,
                        metadata: Self.relativePlayedTime(from: item.playedAt)
                    )
                }
                recentState = rows.isEmpty ? .empty : .loaded(rows)
                selectedIndex = consumePendingSelectionIndex(itemCount: rows.count)
            } catch {
                guard !Task.isCancelled else { return }
                recentState = .error(Self.libraryErrorMessage(error, fallback: "Couldn't load recent tracks."))
            }
        }
    }

    private func fetchQueue(force: Bool) {
        guard isSpotifyConfigured?() != false else {
            presentSetup(clientID: currentConfiguredClientID?() ?? "", hasSavedClientID: hasSavedClientID)
            return
        }
        if !force, queueState.shouldSkipFetch { return }

        queueTask?.cancel()
        queueState = .loading
        selectedIndex = 0
        pendingSelectionOffset = 0
        queueTask = Task {
            do {
                let response = try await apiClient.currentQueue()
                guard !Task.isCancelled else { return }
                var rows: [TrackListItem] = []
                if let currentlyPlaying = response.currentlyPlaying {
                    rows.append(
                        TrackListItem(
                            id: "queue-current-\(currentlyPlaying.id)",
                            track: currentlyPlaying,
                            metadata: "Now playing"
                        )
                    )
                }
                let upcomingTracks = Self.deduplicatedQueueTracks(
                    response.queue,
                    excludingCurrentTrackID: response.currentlyPlaying?.id
                )
                rows.append(
                    contentsOf: upcomingTracks.enumerated().map { index, track in
                        TrackListItem(
                            id: "queue-\(index)-\(track.id)",
                            track: track,
                            metadata: "#\(index + 1) in queue"
                        )
                    }
                )
                queueState = rows.isEmpty ? .empty : .loaded(rows)
                selectedIndex = consumePendingSelectionIndex(itemCount: rows.count)
            } catch {
                guard !Task.isCancelled else { return }
                queueState = .error(Self.libraryErrorMessage(error, fallback: "Couldn't load the queue."))
            }
        }
    }

    private var canShowNowPlaying: Bool {
        switch panelState {
        case .setupRequired, .authenticationRequired:
            return false
        default:
            return true
        }
    }

    private static func makeNowPlayingSummary(from playbackState: SpotifyPlaybackState?) -> NowPlayingSummary? {
        guard let playbackState, let item = playbackState.item else {
            return nil
        }

        return NowPlayingSummary(
            title: item.name,
            artistLine: item.artistLine,
            artworkURL: item.artworkURL,
            isPlaying: playbackState.isPlaying,
            deviceName: playbackState.device?.name,
            progressMs: playbackState.progressMs,
            durationMs: item.durationMs
        )
    }

    private static func relativePlayedTime(from date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Played \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private static func libraryErrorMessage(_ error: Error, fallback: String) -> String {
        if let apiError = error as? SpotifyAPIError {
            switch apiError {
            case .unauthorized:
                return "Reconnect Spotify to enable this view."
            case .message(let message) where message.localizedCaseInsensitiveContains("scope"):
                return "Reconnect Spotify to grant the new permission."
            default:
                return apiError.localizedDescription
            }
        }
        return error.localizedDescription.isEmpty ? fallback : error.localizedDescription
    }

    nonisolated static func deduplicatedQueueTracks(
        _ tracks: [SpotifyTrack],
        excludingCurrentTrackID currentTrackID: String?
    ) -> [SpotifyTrack] {
        var seenTrackIDs = Set<String>()
        if let currentTrackID {
            seenTrackIDs.insert(currentTrackID)
        }

        return tracks.filter { track in
            guard !seenTrackIDs.contains(track.id) else { return false }
            seenTrackIDs.insert(track.id)
            return true
        }
    }
}

private extension TrackCollectionState {
    var shouldSkipFetch: Bool {
        switch self {
        case .loading, .loaded, .empty:
            return true
        case .idle, .error:
            return false
        }
    }

    var hasLoadedContent: Bool {
        if case .loaded = self { return true }
        return false
    }
}
