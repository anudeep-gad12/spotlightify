import AppKit
import SwiftUI

enum SearchPanelLayout {
    /// The visible rounded card.
    static let cardWidth: CGFloat = 760
    static let cardHeight: CGFloat = 660
    static let cornerRadius: CGFloat = 26
    /// Small transparent inset keeps the rounded material clear of the square window edge.
    static let windowInset: CGFloat = 12
    static let windowWidth = cardWidth + windowInset * 2
    static let windowHeight = cardHeight + windowInset * 2
}

struct SearchPanelView: View {
    private enum FocusField: Hashable {
        case search
        case clientID
    }

    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject var appearanceStore: AppearancePreferenceStore
    let onAppearanceChanged: (AppearancePreference) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: FocusField?
    @State private var seekPreviewFraction: CGFloat?
    @State private var isSeekHovered = false
    @State private var isSeekDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField

            if shouldShowModeSwitcher {
                modeSwitcher
            }

            if let message = viewModel.inlineMessage {
                inlineMessage(message)
            }

            resultsSurface

            if shouldShowNowPlayingCard {
                nowPlayingCard
            }

            footer
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: SearchPanelLayout.cardWidth, height: SearchPanelLayout.cardHeight)
        .modifier(NativePanelSurface(
            reduceTransparency: reduceTransparency,
            appearance: appearanceStore.preference
        ))
        .padding(SearchPanelLayout.windowInset)
        .frame(width: SearchPanelLayout.windowWidth, height: SearchPanelLayout.windowHeight)
        .preferredColorScheme(appearanceStore.preference.preferredColorScheme)
        .onAppear {
            requestFocus()
        }
        .onChange(of: viewModel.focusRequestID) {
            requestFocus()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                Image("LogoMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text("Spotlightify")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .tracking(-0.35)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                WindowDragRegion()
            }
            .help("Drag to move Spotlightify")

            HStack(spacing: 8) {
                openSpotifyButton
                appearanceControls
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var appearanceControls: some View {
        HStack(spacing: 2) {
            ForEach(AppearancePreference.allCases, id: \.self) { preference in
                let selected = appearanceStore.preference == preference
                Button {
                    onAppearanceChanged(preference)
                } label: {
                    Image(systemName: preference.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(SelectedModeSurface(isSelected: selected))
                .help("Theme: \(preference.title)")
                .accessibilityLabel("Theme: \(preference.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var openSpotifyButton: some View {
        Button {
            viewModel.requestOpenSpotify()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 11, weight: .medium))

                Text("Open Spotify")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .modifier(NativeGlassButtonStyle())
        .help("Open the Spotify desktop app")
    }

    private var searchField: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Color.inkMuted)

            TextField("Search tracks or artists", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(Color.ink)
                .focused($focusedField, equals: .search)
                .disabled(isSetupState)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.inkMuted)
                }
                .buttonStyle(.plain)
                .disabled(isSetupState)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Color.separator.frame(height: 1) }
        .opacity(isSetupState ? 0.64 : 1)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 7) {
            ForEach(SearchPanelMode.allCases) { mode in
                let selected = viewModel.activeMode == mode
                Button {
                    viewModel.setMode(mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                        .frame(minWidth: 72)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .modifier(SelectedModeSurface(isSelected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func inlineMessage(_ message: String) -> some View {
        HStack(spacing: 10) {
            if viewModel.inlineMessageIsLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.playingDot)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: viewModel.inlineMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(viewModel.inlineMessageIsError ? Color.orange : Color.inkMuted)
            }

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.inlineMessageIsError ? Color.orange.opacity(0.95) : Color.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(viewModel.inlineMessageIsError ? Color.orange.opacity(0.10) : Color.overlayInk.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(viewModel.inlineMessageIsError ? Color.orange.opacity(0.18) : Color.separator, lineWidth: 1)
        )
    }

    private var resultsSurface: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: main list
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text(sectionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                        .textCase(.uppercase)

                    Spacer()

                    sectionMeta
                }

                Rectangle()
                    .fill(Color.separator.opacity(0.7))
                    .frame(height: 1)

                content
            }

            // Right: album detail panel
            if viewModel.selectedAlbum != nil {
                albumDetailPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewModel.selectedAlbum?.id)
    }

    @ViewBuilder
    private var albumDetailPanel: some View {
        if let album = viewModel.selectedAlbum {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Text("Album")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                        .textCase(.uppercase)

                    Spacer()

                    Button {
                        viewModel.closeAlbumDetail()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .buttonStyle(.plain)
                }

                Rectangle()
                    .fill(Color.separator.opacity(0.7))
                    .frame(height: 1)

                // Album info
                HStack(spacing: 12) {
                    AsyncImage(url: album.artworkURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.overlayInk.opacity(0.055))
                            .overlay {
                                Image(systemName: "square.stack")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.inkFaint)
                            }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)

                        Text(album.artistLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.inkMuted)
                            .lineLimit(1)

                        if let total = album.totalTracks {
                            Text("\(total) tracks")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                }
                .padding(.top, 2)

                // Tracks
                switch viewModel.albumTracksState {
                case .idle, .loading:
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            SkeletonTrackRow(index: index)
                        }
                    }
                case .loaded(let items):
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    AlbumTrackRow(item: item, index: index, isSelected: index == viewModel.albumTrackSelectedIndex)
                                        .id(item.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            Task { await viewModel.onPlayRequested?(item.track) }
                                        }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: viewModel.albumTrackSelectedIndex) {
                            guard items.indices.contains(viewModel.albumTrackSelectedIndex) else { return }
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                                proxy.scrollTo(items[viewModel.albumTrackSelectedIndex].id, anchor: .center)
                            }
                        }
                    }
                case .empty:
                    Text("No tracks found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, 8)
                case .error(let message):
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .padding(.top, 8)
                }
            }
            .padding(.leading, 20)
            .frame(width: 250)
        }
    }

    @ViewBuilder
    private var nowPlayingCard: some View {
        switch viewModel.nowPlayingState {
        case .hidden:
            EmptyView()
        case .loading:
            bottomDock(
                artworkURL: nil,
                title: "checking current playback",
                artistLine: "Spotify is syncing what’s on right now.",
                isPlaying: false,
                deviceName: nil,
                progressFraction: nil,
                durationMs: nil,
                isRefreshing: false
            )
        case .showing(let summary):
            bottomDock(
                artworkURL: summary.artworkURL,
                title: summary.title,
                artistLine: summary.artistLine,
                isPlaying: summary.isPlaying,
                deviceName: summary.deviceName,
                progressFraction: summary.progressFraction,
                durationMs: summary.durationMs,
                isRefreshing: viewModel.nowPlayingRefreshInProgress
            )
        }
    }

    private func bottomDock(
        artworkURL: URL?,
        title: String,
        artistLine: String,
        isPlaying: Bool,
        deviceName: String?,
        progressFraction: CGFloat?,
        durationMs: Int?,
        isRefreshing: Bool
    ) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.overlayInk.opacity(0.055))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                    }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("now playing")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)

                    Circle()
                        .fill(isPlaying ? Color.playingDot : Color.orange.opacity(0.85))
                        .frame(width: 6, height: 6)

                    Text(isPlaying ? "playing" : "paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.inkMuted)

                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.playingDot)
                            .frame(width: 10, height: 10)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isRefreshing)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Text(artistLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)

                seekBar(progressFraction, durationMs: durationMs)
            }

            Spacer(minLength: 0)

            if let deviceName, !deviceName.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("device")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)

                    Text(deviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: 120, alignment: .trailing)
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Color.separator.frame(height: 1) }
    }

    private func seekBar(_ progressFraction: CGFloat?, durationMs: Int?) -> some View {
        let displayedFraction = seekPreviewFraction ?? progressFraction ?? 0
        let displayedPositionMs = durationMs.map { Int(CGFloat($0) * displayedFraction) }

        return HStack(spacing: 9) {
            Text(formatPlaybackTime(displayedPositionMs))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 34, alignment: .trailing)

            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let thumbDiameter: CGFloat = 10
                let progressWidth = trackWidth * displayedFraction
                let thumbOffset = min(max(progressWidth - thumbDiameter / 2, 0), max(0, trackWidth - thumbDiameter))
                let tooltipWidth: CGFloat = 48
                let tooltipOffset = min(max(progressWidth - tooltipWidth / 2, 0), max(0, trackWidth - tooltipWidth))
                let expanded = isSeekHovered || isSeekDragging

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.overlayInk.opacity(expanded ? 0.14 : 0.09))
                        .frame(height: expanded ? 4 : 2)

                    if progressFraction != nil {
                        Capsule(style: .continuous)
                            .fill(Color.playingDot.opacity(expanded ? 0.95 : 0.76))
                            .frame(width: progressWidth, height: expanded ? 4 : 2)
                    }

                    if progressFraction != nil, expanded || seekPreviewFraction != nil {
                        Circle()
                            .fill(Color.ink)
                            .frame(width: thumbDiameter, height: thumbDiameter)
                            .overlay(
                                Circle()
                                    .stroke(Color.panelCanvas.opacity(0.85), lineWidth: 1)
                            )
                            .shadow(color: Color.panelShadow.opacity(0.42), radius: 4, y: 2)
                            .offset(x: thumbOffset)
                    }

                    if isSeekDragging {
                        Text(formatPlaybackTime(displayedPositionMs))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.onPrimary)
                            .frame(width: tooltipWidth)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.ink)
                            )
                            .shadow(color: Color.panelShadow.opacity(0.55), radius: 7, y: 3)
                            .offset(x: tooltipOffset, y: -28)
                            .zIndex(1)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        isSeekHovered = hovering
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard durationMs != nil, trackWidth > 0 else { return }
                            isSeekDragging = true
                            seekPreviewFraction = min(max(value.location.x / trackWidth, 0), 1)
                        }
                        .onEnded { value in
                            guard let durationMs, trackWidth > 0 else {
                                isSeekDragging = false
                                return
                            }
                            let fraction = min(max(value.location.x / trackWidth, 0), 1)
                            seekPreviewFraction = fraction
                            isSeekDragging = false
                            viewModel.requestSeek(to: Int(CGFloat(durationMs) * fraction))

                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                if seekPreviewFraction == fraction {
                                    seekPreviewFraction = nil
                                }
                            }
                        }
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: expanded)
            }
            .frame(height: 18)

            Text(formatPlaybackTime(durationMs))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 34, alignment: .leading)
        }
        .frame(height: 18)
        .help(durationMs == nil ? "Playback position unavailable" : "Click or drag to seek")
        .onChange(of: progressFraction) {
            seekPreviewFraction = nil
        }
    }

    private func formatPlaybackTime(_ milliseconds: Int?) -> String {
        guard let milliseconds else { return "--:--" }
        let totalSeconds = max(0, milliseconds / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private var sectionMeta: some View {
        Text(sectionMetaText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.inkMuted)
    }

    @ViewBuilder
    private var content: some View {
        if case .setupRequired = viewModel.panelState {
            setupContent
        } else if case .authenticationRequired(let message) = viewModel.panelState {
            authenticationContent(message)
        } else {
            switch viewModel.activeMode {
            case .search:
                searchContent
            case .recent:
                collectionContent(
                    state: viewModel.recentState,
                    loadingIcon: "clock.arrow.circlepath",
                    loadingTitle: "Loading recent tracks",
                    loadingSubtitle: "Pulling the last songs Spotify says you played.",
                    emptyIcon: "clock",
                    emptyTitle: "No recent tracks yet",
                    emptySubtitle: "Play something in Spotify, then open this again."
                )
            case .queue:
                collectionContent(
                    state: viewModel.queueState,
                    loadingIcon: "list.bullet.rectangle",
                    loadingTitle: "Loading queue",
                    loadingSubtitle: "Checking what Spotify has lined up next.",
                    emptyIcon: "text.line.first.and.arrowtriangle.forward",
                    emptyTitle: "Queue is empty",
                    emptySubtitle: "Queue a track from search or recent tracks."
                )
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.panelState {
        case .helper:
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(Color.inkMuted)

                Text("Search your music")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)

                Text("Tracks, artists, and albums in one place")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            loadingState(
                icon: "waveform.and.magnifyingglass",
                title: "Searching Spotify",
                subtitle: "Pulling the strongest matches from the catalog."
            )
        case .empty:
            emptyState(
                icon: "music.note",
                title: "No matches found",
                subtitle: "Try a shorter phrase or search by artist first."
            )
        case .error(let message):
            emptyState(
                icon: "exclamationmark.octagon.fill",
                title: "Something went wrong",
                subtitle: message,
                tint: .orange
            )
        case .results:
            trackList(viewModel.searchItems)
        case .setupRequired, .authenticationRequired:
            EmptyView()
        }
    }

    @ViewBuilder
    private func collectionContent(
        state: TrackCollectionState,
        loadingIcon: String,
        loadingTitle: String,
        loadingSubtitle: String,
        emptyIcon: String,
        emptyTitle: String,
        emptySubtitle: String
    ) -> some View {
        switch state {
        case .idle, .loading:
            loadingState(icon: loadingIcon, title: loadingTitle, subtitle: loadingSubtitle)
        case .loaded(let items):
            trackList(items)
        case .empty:
            emptyState(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
        case .error(let message):
            emptyState(
                icon: "exclamationmark.octagon.fill",
                title: "Couldn’t load this view",
                subtitle: message,
                tint: .orange
            )
        }
    }

    private func authenticationContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            emptyState(
                icon: "person.crop.circle.badge.checkmark",
                title: "Connect Spotify",
                subtitle: message
            )

            Button(viewModel.loginInProgress ? "Waiting For Spotify..." : "Login / Reconnect") {
                viewModel.requestLogin()
            }
            .modifier(NativeGlassButtonStyle(prominent: true))
            .disabled(viewModel.loginInProgress)
            .controlSize(.large)
            .font(.system(size: 14, weight: .bold))
        }
    }

    private func loadingState(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.lowercased())
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.inkSecondary)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { index in
                        SkeletonTrackRow(index: index)
                    }
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func trackList(_ items: [TrackListItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TrackListRow(item: item, index: index, isSelected: index == viewModel.selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.select(index: index)
                                viewModel.playSelected()
                            }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.selectedIndex) {
                guard items.indices.contains(viewModel.selectedIndex) else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                    proxy.scrollTo(items[viewModel.selectedIndex].id, anchor: .center)
                }
            }
        }
    }

    private var setupContent: some View {
        ScrollView { setupForm }
            .scrollIndicators(.hidden)
    }

    private var setupForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bring your own Spotify app")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink)

                Text("Create a Spotify developer app, add the redirect below, then paste its Client ID here. The value stays local to this Mac.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                setupStep(number: "1", title: "Spotify redirect URI", detail: viewModel.redirectURI, emphasis: true)
                setupStep(number: "2", title: "Allowed API", detail: "Enable Spotify Web API for the app.")
                setupStep(number: "3", title: "Paste Client ID", detail: "Client secret is not used and should never be stored here.")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Spotify Client ID")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(.uppercase)
                    .tracking(1.3)

                TextField("32-character Client ID", text: $viewModel.setupClientID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.ink)
                    .focused($focusedField, equals: .clientID)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .modifier(NativeGlassBackground(cornerRadius: 18))
            }

            HStack(spacing: 12) {
                Button("Save Client ID") {
                    viewModel.saveClientID()
                }
                .modifier(NativeGlassButtonStyle(prominent: true))
                .controlSize(.large)
                .font(.system(size: 14, weight: .bold))

                if viewModel.hasSavedClientID {
                    Button("Clear Saved Setup") {
                        viewModel.clearConfiguration()
                    }
                    .modifier(NativeGlassButtonStyle())
                    .controlSize(.large)
                    .font(.system(size: 14, weight: .bold))
                }
            }

        }
    }

    private func setupStep(number: String, title: String, detail: String, emphasis: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.overlayInk.opacity(0.055))
                )
                .overlay(
                    Circle()
                        .stroke(Color.separator, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.inkSecondary)

                Text(detail)
                    .font(.system(size: emphasis ? 13 : 14, weight: emphasis ? .bold : .medium, design: emphasis ? .monospaced : .default))
                    .foregroundStyle(emphasis ? Color.inkSecondary : Color.inkMuted)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.overlayInk.opacity(0.026))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.overlayInk.opacity(0.065), lineWidth: 1)
        )
    }

    private func emptyState(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color = .green
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.lowercased())
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint == .orange ? Color.orange.opacity(0.95) : Color.inkSecondary)

            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 10)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            if !isSetupState {
                keyboardHint("↵", "Play")
                keyboardHint("⌘↵", "Queue")
                keyboardHint("↑ ↓", "Select")
                keyboardHint("Tab", "Switch")
            }
            Spacer(minLength: 0)
            keyboardHint("Esc", "Close")
        }
    }

    private var sectionTitle: String {
        if case .setupRequired = viewModel.panelState {
            return "Setup"
        }
        if case .authenticationRequired = viewModel.panelState {
            return "Connection"
        }

        switch viewModel.activeMode {
        case .search:
            switch viewModel.panelState {
            case .results:
                return "Results"
            case .loading:
                return "Searching"
            case .empty:
                return "No Results"
            case .error:
                return "Error"
            default:
                return "Discover"
            }
        case .recent:
            return "Recent"
        case .queue:
            return "Queue"
        }
    }

    private var sectionMetaText: String {
        if case .setupRequired = viewModel.panelState {
            return "First launch"
        }
        if case .authenticationRequired = viewModel.panelState {
            return "Reconnect"
        }

        switch viewModel.activeMode {
        case .search:
            if case .results(let rows) = viewModel.panelState {
                let albumCount = rows.filter { if case .album = $0 { return true }; return false }.count
                let trackCount = rows.filter { if case .track = $0 { return true }; return false }.count
                return "\(trackCount) tracks, \(albumCount) albums"
            }
            return "Top 8"
        case .recent:
            if case .loaded(let items) = viewModel.recentState {
                return "Last \(items.count) tracks"
            }
            return "Last 20"
        case .queue:
            if case .loaded(let items) = viewModel.queueState {
                let upcoming = max(0, items.count - 1)
                return upcoming == 1 ? "Now playing + 1 upcoming" : "Now playing + \(upcoming) upcoming"
            }
            return "Current session"
        }
    }

    private var isSetupState: Bool {
        if case .setupRequired = viewModel.panelState {
            return true
        }
        return false
    }

    private var shouldShowModeSwitcher: Bool {
        switch viewModel.panelState {
        case .setupRequired, .authenticationRequired:
            return false
        default:
            return true
        }
    }

    private var shouldShowNowPlayingCard: Bool {
        switch viewModel.panelState {
        case .setupRequired, .authenticationRequired:
            return false
        case .helper, .loading, .results, .empty, .error:
            if case .hidden = viewModel.nowPlayingState {
                return false
            }
            return true
        }
    }

    private func keyboardHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.inkSecondary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func requestFocus() {
        DispatchQueue.main.async {
            focusedField = isSetupState ? .clientID : .search
        }
    }
}

private struct TrackListRow: View {
    let item: TrackListItem
    let index: Int
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: SpotifyTrack {
        item.track
    }

    private var isAlbumRow: Bool {
        item.id.hasPrefix("album-")
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? Color.ink : Color.inkFaint)
                .frame(width: 28, alignment: .leading)

            AsyncImage(url: track.artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.overlayInk.opacity(0.055))
                    .overlay {
                        Image(systemName: isAlbumRow ? "square.stack" : "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                    }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.artistLine)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)

                    if isAlbumRow {
                        albumChip
                    }

                    if let metadata = item.metadata {
                        Text("•")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.inkFaint)

                        Text(metadata)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 10)

            if let duration = track.durationMs {
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.overlayInk.opacity(0.065) : isHovered ? Color.overlayInk.opacity(0.030) : Color.clear)
        )
        .overlay(
            Rectangle()
                .fill(Color.separator.opacity(0.48))
                .frame(height: 1),
            alignment: .bottom
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var albumChip: some View {
        Text("Album")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.overlayInk.opacity(0.10))
            )
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct AlbumTrackRow: View {
    let item: TrackListItem
    let index: Int
    let isSelected: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: SpotifyTrack {
        item.track
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? Color.ink : Color.inkFaint)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Text(track.artistLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let duration = track.durationMs {
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.overlayInk.opacity(0.065) : isHovered ? Color.overlayInk.opacity(0.030) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct SkeletonTrackRow: View {
    let index: Int

    var body: some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint.opacity(0.55))
                .frame(width: 28, alignment: .leading)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.overlayInk.opacity(0.055))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 7) {
                Capsule(style: .continuous)
                    .fill(Color.overlayInk.opacity(0.075))
                    .frame(width: 230, height: 10)

                Capsule(style: .continuous)
                    .fill(Color.overlayInk.opacity(0.045))
                    .frame(width: 130, height: 8)
            }

            Spacer(minLength: 0)

            Capsule(style: .continuous)
                .fill(Color.overlayInk.opacity(0.045))
                .frame(width: 34, height: 9)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .overlay(
            Rectangle()
                .fill(Color.separator.opacity(0.36))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

private extension NowPlayingSummary {
    var progressFraction: CGFloat? {
        guard let progressMs, let durationMs, durationMs > 0 else { return nil }
        return min(max(CGFloat(progressMs) / CGFloat(durationMs), 0), 1)
    }
}

private struct NativePanelSurface: ViewModifier {
    let reduceTransparency: Bool
    let appearance: AppearancePreference

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(.rect(cornerRadius: SearchPanelLayout.cornerRadius))
        } else {
            content
                .background {
                    PanelMaterial(appearance: appearance)
                        .clipShape(.rect(cornerRadius: SearchPanelLayout.cornerRadius))
                }
                .clipShape(.rect(cornerRadius: SearchPanelLayout.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SearchPanelLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.separator.opacity(0.65), lineWidth: 1)
                }
        }
    }
}

private struct SelectedModeSurface: ViewModifier {
    let isSelected: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected, !reduceTransparency, #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else if isSelected {
            content.background(Color.overlayInk.opacity(0.10), in: .capsule)
        } else {
            content
        }
    }
}

private struct NativeGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: cornerRadius))
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

private struct NativeGlassButtonStyle: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct PanelMaterial: NSViewRepresentable {
    let appearance: AppearancePreference

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance.appKitAppearance
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = appearance.appKitAppearance
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

private extension AppearancePreference {
    var symbolName: String {
        switch self {
        case .system:
            return "display"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private extension Color {
    static let panelCanvas = Color(nsColor: .windowBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let inkSecondary = Color(nsColor: .secondaryLabelColor)
    static let inkMuted = Color(nsColor: .secondaryLabelColor)
    static let inkFaint = Color(nsColor: .secondaryLabelColor).opacity(0.85)
    static let overlayInk = Color(nsColor: .labelColor)
    static let onPrimary = Color(nsColor: .windowBackgroundColor)
    static let panelShadow = Color(nsColor: .shadowColor)
    static let separator = Color(nsColor: .separatorColor)
    static let playingDot = Color(nsColor: NSColor(calibratedRed: 0.337, green: 0.827, blue: 0.392, alpha: 1.0))
}
