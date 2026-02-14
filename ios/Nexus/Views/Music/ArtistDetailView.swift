import SwiftUI
import MusicKit
import os

/// Detail view for an artist showing their albums and top songs
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject private var musicService = MusicKitService.shared
    @State private var albums: MusicItemCollection<Album>?
    @State private var topSongs: MusicItemCollection<Song>?
    @State private var isLoading = true

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "music")

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Artist Header
                artistHeader

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // Top Songs
                    if let songs = topSongs, !songs.isEmpty {
                        topSongsSection(songs)
                    }

                    // Albums
                    if let albums = albums, !albums.isEmpty {
                        albumsSection(albums)
                    }
                }
            }
            .padding()
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadArtistContent()
        }
    }

    // MARK: - Artist Header

    private var artistHeader: some View {
        VStack(spacing: 16) {
            if let artwork = artist.artwork {
                ArtworkImage(artwork, width: 200, height: 200)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .clipped()
                    .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
            } else {
                Circle()
                    .fill(NexusTheme.Colors.cardAlt)
                    .frame(width: 200, height: 200)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                    )
            }

            Text(artist.name)
                .font(.title.bold())

            // Play/Shuffle buttons
            HStack(spacing: 16) {
                Button {
                    Task {
                        if let songs = topSongs {
                            await musicService.playSongs(Array(songs))
                        }
                    }
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
                    Task {
                        if let songs = topSongs {
                            await musicService.playSongs(Array(songs), shuffle: true)
                        }
                    }
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

    // MARK: - Top Songs Section

    private func topSongsSection(_ songs: MusicItemCollection<Song>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Songs")
                .font(.title2.bold())

            LazyVStack(spacing: 0) {
                ForEach(Array(songs.prefix(10).enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 24)

                        if let artwork = song.artwork {
                            ArtworkImage(artwork, width: 44, height: 44)
                                .frame(width: 44, height: 44)
                                .cornerRadius(4)
                                .clipped()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline)
                                .lineLimit(1)

                            Text(song.albumTitle ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Menu {
                            Button(action: { Task { await musicService.playSong(song) }}) {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button(action: { Task { await musicService.playNext(song) }}) {
                                Label("Play Next", systemImage: "text.insert")
                            }
                            Button(action: { Task { await musicService.addToQueue(song) }}) {
                                Label("Add to Queue", systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await musicService.playSong(song) }
                    }
                }
            }
        }
    }

    // MARK: - Albums Section

    private func albumsSection(_ albums: MusicItemCollection<Album>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(albums, id: \.id) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let artwork = album.artwork {
                                ArtworkImage(artwork, width: 150, height: 150)
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(8)
                                    .clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(NexusTheme.Colors.cardAlt)
                                    .frame(width: 150, height: 150)
                            }

                            Text(album.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            if let year = album.releaseDate?.formatted(.dateTime.year()) {
                                Text(year)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 150)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadArtistContent() async {
        isLoading = true

        do {
            // Fetch artist with relationships
            var request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: artist.id)
            request.properties = [.albums, .topSongs]
            let response = try await request.response()

            if let fullArtist = response.items.first {
                albums = fullArtist.albums
                topSongs = fullArtist.topSongs
            }
        } catch {
            logger.error("Failed to load artist content: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

#Preview {
    NavigationView {
        Text("Artist Detail Preview")
    }
}
