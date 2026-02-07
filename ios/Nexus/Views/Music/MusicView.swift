import SwiftUI
import MusicKit

/// Main music hub view with Apple Music integration
struct MusicView: View {
    @ObservedObject private var musicService = MusicKitService.shared
    @ObservedObject private var loggingService = MusicService.shared
    @State private var showFullPlayer = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if !musicService.isAuthorized {
                authorizationView
            } else {
                mainContent
            }

            // Mini player overlay
            if musicService.isAuthorized && musicService.currentEntry != nil {
                VStack(spacing: 0) {
                    Spacer()
                    MiniPlayerView(musicService: musicService, showFullPlayer: $showFullPlayer)
                        .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if musicService.isAuthorized {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            NavigationView {
                MusicSearchView()
            }
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            MusicPlayerView(musicService: musicService)
        }
    }

    // MARK: - Authorization

    private var authorizationView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Apple Music")
                    .font(.title.bold())

                Text("Play music, browse your library, and track listening activity.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task {
                    let granted = await musicService.requestAuthorization()
                    if granted && AppSettings.shared.musicLoggingEnabled {
                        loggingService.startObserving()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "applelogo")
                    Text("Connect")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.pink, .red], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(14)
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .background(Color.nexusBackground)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Now Playing Hero
                nowPlayingHero
                    .padding(.horizontal)

                // Quick Actions
                quickActionsRow
                    .padding(.horizontal)

                // Playlists Section
                if !musicService.userPlaylists.isEmpty {
                    playlistsSection
                }

                // Browse Section
                browseSection
                    .padding(.horizontal)

                // Today's Stats
                if loggingService.todayEvents.count > 0 {
                    statsSection
                        .padding(.horizontal)
                }

                // Spacer for mini player
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.nexusBackground)
        .refreshable {
            await musicService.loadLibraryData()
            await loggingService.fetchTodayEvents()
        }
        .task {
            await loggingService.fetchTodayEvents()
        }
    }

    // MARK: - Now Playing Hero

    private var nowPlayingHero: some View {
        Button { showFullPlayer = true } label: {
            HStack(spacing: 16) {
                // Artwork
                ZStack {
                    if let artwork = musicService.artwork {
                        ArtworkImage(artwork, width: 72, height: 72)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.title)
                                    .foregroundColor(.pink)
                            )
                    }

                    // Playing indicator
                    if musicService.isPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundColor(.pink)
                                    .symbolEffect(.variableColor.iterative)
                            )
                            .offset(x: 28, y: 28)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if musicService.currentEntry != nil {
                        Text("NOW PLAYING")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.pink)

                        Text(musicService.currentTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(musicService.currentArtist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Nothing Playing")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Tap to browse music")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Play/Pause
                if musicService.currentEntry != nil {
                    Button {
                        musicService.togglePlayPause()
                    } label: {
                        Image(systemName: musicService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.pink)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.nexusCardBackground)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: MusicLibraryView()) {
                quickActionButton(icon: "music.note.list", title: "Library", color: .blue)
            }

            NavigationLink(destination: QueueView()) {
                quickActionButton(icon: "list.bullet", title: "Queue", color: .orange)
            }

            Button {
                Task { await playShuffleAll() }
            } label: {
                quickActionButton(icon: "shuffle", title: "Shuffle", color: .green)
            }
        }
    }

    private func quickActionButton(icon: String, title: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Playlists Section

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Playlists")
                    .font(.title3.weight(.semibold))

                Spacer()

                NavigationLink(destination: MusicLibraryView()) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.pink)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(musicService.userPlaylists.prefix(10), id: \.id) { playlist in
                        PlaylistCard(playlist: playlist)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Browse Section

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse")
                .font(.title3.weight(.semibold))

            VStack(spacing: 8) {
                NavigationLink(destination: MusicSearchView()) {
                    browseRow(icon: "magnifyingglass", title: "Search", subtitle: "Find songs, albums, artists")
                }

                NavigationLink(destination: MusicLibraryView()) {
                    browseRow(icon: "square.stack", title: "Albums", subtitle: "Your album collection")
                }

                NavigationLink(destination: MusicLibraryView()) {
                    browseRow(icon: "music.mic", title: "Artists", subtitle: "Artists you follow")
                }
            }
        }
    }

    private func browseRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.nexusCardBackground)
        )
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title3.weight(.semibold))

            HStack(spacing: 16) {
                statCard(
                    value: "\(loggingService.todayEvents.count)",
                    label: "Tracks",
                    icon: "music.note",
                    color: .pink
                )

                statCard(
                    value: totalListeningTime,
                    label: "Listening",
                    icon: "clock",
                    color: .purple
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.semibold))

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.nexusCardBackground)
        )
    }

    // MARK: - Helpers

    private var totalListeningTime: String {
        let totalSeconds = loggingService.todayEvents.compactMap { $0.durationSec }.reduce(0, +)
        let minutes = totalSeconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func playShuffleAll() async {
        // Play first playlist shuffled, or do nothing if no playlists
        if let firstPlaylist = musicService.userPlaylists.first {
            await musicService.playPlaylist(firstPlaylist)
            musicService.toggleShuffle()
        }
    }
}

// MARK: - Playlist Card

struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            VStack(alignment: .leading, spacing: 8) {
                // Artwork
                if let artwork = playlist.artwork {
                    ArtworkImage(artwork, width: 140, height: 140)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .font(.largeTitle)
                                .foregroundColor(.pink)
                        )
                }

                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let curator = playlist.curatorName {
                    Text(curator)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    let playlist: Playlist
    @StateObject private var musicService = MusicKitService.shared
    @State private var tracks: MusicItemCollection<Track>?
    @State private var isLoading = true

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: 16) {
                    if let artwork = playlist.artwork {
                        ArtworkImage(artwork, width: 200, height: 200)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    }

                    Text(playlist.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    if let description = playlist.standardDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 16) {
                        Button {
                            Task { await musicService.playPlaylist(playlist) }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.pink)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button {
                            Task {
                                await musicService.playPlaylist(playlist)
                                musicService.toggleShuffle()
                            }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.pink.opacity(0.15))
                                .foregroundColor(.pink)
                                .cornerRadius(10)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Tracks
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let tracks = tracks {
                Section("Tracks") {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, index: index + 1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTracks()
        }
    }

    private func loadTracks() async {
        isLoading = true
        do {
            let detailed = try await playlist.with([.tracks])
            tracks = detailed.tracks
        } catch {
            // Handle error
        }
        isLoading = false
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    let index: Int
    @StateObject private var musicService = MusicKitService.shared

    var body: some View {
        Button {
            Task {
                if case let .song(song) = track {
                    await musicService.playSong(song)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                if let artwork = track.artwork {
                    ArtworkImage(artwork, width: 44, height: 44)
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let duration = track.duration {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationView {
        MusicView()
    }
}
