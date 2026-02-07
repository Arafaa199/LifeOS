import SwiftUI
import MusicKit
import os

/// Detail view for an album showing all tracks
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject private var musicService = MusicKitService.shared
    @State private var tracks: MusicItemCollection<Track>?
    @State private var isLoading = true

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "music")

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Album Header
                albumHeader
                    .padding(.bottom, 24)

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let tracks = tracks {
                    // Track List
                    trackList(tracks)
                }
            }
            .padding()
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAlbumTracks()
        }
    }

    // MARK: - Album Header

    private var albumHeader: some View {
        VStack(spacing: 16) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 240, height: 240)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 240, height: 240)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    )
            }

            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(album.artistName)
                    .font(.headline)
                    .foregroundColor(NexusTheme.Colors.accent)

                HStack(spacing: 4) {
                    if let releaseDate = album.releaseDate {
                        Text(releaseDate.formatted(.dateTime.year()))
                    }
                    if let genre = album.genreNames.first {
                        Text("•")
                        Text(genre)
                    }
                    if album.trackCount > 0 {
                        Text("•")
                        Text("\(album.trackCount) songs")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Play/Shuffle buttons
            HStack(spacing: 16) {
                Button {
                    Task { await musicService.playAlbum(album) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NexusTheme.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button {
                    Task { await musicService.playAlbum(album, shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Track List

    private func trackList(_ tracks: MusicItemCollection<Track>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                trackRow(track, index: index + 1)

                if index < tracks.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }

    private func trackRow(_ track: Track, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)

                if track.artistName != album.artistName {
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Menu {
                Button(action: { playTrack(track) }) {
                    Label("Play", systemImage: "play.fill")
                }
                Button(action: { playNextTrack(track) }) {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button(action: { addToQueue(track) }) {
                    Label("Add to Queue", systemImage: "plus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            playTrack(track)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func playTrack(_ track: Track) {
        Task {
            if case .song(let song) = track {
                await musicService.playSong(song)
            }
        }
    }

    private func playNextTrack(_ track: Track) {
        Task {
            if case .song(let song) = track {
                await musicService.playNext(song)
            }
        }
    }

    private func addToQueue(_ track: Track) {
        Task {
            if case .song(let song) = track {
                await musicService.addToQueue(song)
            }
        }
    }

    // MARK: - Data Loading

    private func loadAlbumTracks() async {
        isLoading = true

        do {
            var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            request.properties = [.tracks]
            let response = try await request.response()

            if let fullAlbum = response.items.first {
                tracks = fullAlbum.tracks
            }
        } catch {
            logger.error("Failed to load album tracks: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

#Preview {
    NavigationView {
        Text("Album Detail Preview")
    }
}
