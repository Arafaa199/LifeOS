import SwiftUI
import MusicKit

/// Main music hub view with Apple Music integration
struct MusicView: View {
    @StateObject private var musicKitService = MusicKitService.shared
    @StateObject private var musicService = MusicService.shared  // For logging
    @State private var showFullPlayer = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if !musicKitService.isAuthorized {
                authorizationView
            } else {
                mainContent
            }

            // Mini player
            if musicKitService.isAuthorized {
                VStack(spacing: 0) {
                    Spacer()
                    MiniPlayerView(musicService: musicKitService, showFullPlayer: $showFullPlayer)
                }
            }
        }
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showFullPlayer) {
            MusicPlayerView(musicService: musicKitService)
        }
    }

    // MARK: - Authorization

    private var authorizationView: some View {
        VStack(spacing: 24) {
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

                Text("Connect to Apple Music to play songs, browse your library, and discover new music.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task {
                    let granted = await musicKitService.requestAuthorization()
                    if granted && AppSettings.shared.musicLoggingEnabled {
                        musicService.startObserving()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "applelogo")
                    Text("Connect to Apple Music")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.pink, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(Color.nexusBackground)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            // Now Playing Section
            if musicKitService.currentEntry != nil {
                Section {
                    Button(action: { showFullPlayer = true }) {
                        nowPlayingCard
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            // Quick Access
            Section {
                NavigationLink(destination: MusicSearchView()) {
                    Label("Search", systemImage: "magnifyingglass")
                }

                NavigationLink(destination: MusicLibraryView()) {
                    Label("Library", systemImage: "music.note.house")
                }

                NavigationLink(destination: QueueView()) {
                    Label("Queue", systemImage: "list.bullet")
                }
            }

            // User Playlists
            if !musicKitService.userPlaylists.isEmpty {
                Section("Your Playlists") {
                    ForEach(musicKitService.userPlaylists.prefix(5), id: \.id) { playlist in
                        PlaylistRow(playlist: playlist)
                    }

                    if musicKitService.userPlaylists.count > 5 {
                        NavigationLink(destination: MusicLibraryView()) {
                            Text("See All")
                                .foregroundColor(.nexusPrimary)
                        }
                    }
                }
            }

            // Listening Stats (from MusicService logging)
            Section("Today's Activity") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(musicService.todayEvents.count)")
                            .font(.title.bold())
                        Text("Tracks Played")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(totalListeningTime)
                            .font(.title.bold())
                        Text("Listening Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                if musicService.pendingCount > 0 {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.orange)
                        Text("\(musicService.pendingCount) tracks pending sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Recent Tracks
            if !musicService.todayEvents.isEmpty {
                Section("Recent") {
                    ForEach(musicService.todayEvents.prefix(10)) { event in
                        RecentTrackRow(event: event)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nexusBackground)
        .refreshable {
            await musicKitService.loadLibraryData()
            await musicService.fetchTodayEvents()
        }
        .task {
            await musicService.fetchTodayEvents()
        }
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        HStack(spacing: 16) {
            // Artwork
            if let artwork = musicKitService.artwork {
                ArtworkImage(artwork, width: 80, height: 80)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("NOW PLAYING")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.nexusPrimary)

                Text(musicKitService.currentTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(musicKitService.currentArtist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Play/Pause button
            Button(action: musicKitService.togglePlayPause) {
                Image(systemName: musicKitService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.nexusPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.nexusCardBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }

    // MARK: - Helpers

    private var totalListeningTime: String {
        let totalSeconds = musicService.todayEvents.compactMap { $0.durationSec }.reduce(0, +)
        let minutes = totalSeconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Recent Track Row

private struct RecentTrackRow: View {
    let event: ListeningEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundColor(.pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.trackTitle)
                    .font(.subheadline)
                    .lineLimit(1)

                if let artist = event.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let duration = event.durationSec {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var timeString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: event.startedAt) else { return "" }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.timeZone = TimeZone(identifier: "Asia/Dubai")
        return timeFormatter.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationView {
        MusicView()
    }
}
