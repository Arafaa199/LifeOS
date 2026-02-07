import SwiftUI
import MusicKit
import os

private let musicLogger = Logger(subsystem: "com.nexus.lifeos", category: "music")

/// Browse user's music library
struct MusicLibraryView: View {
    @ObservedObject var musicService = MusicKitService.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $selectedTab) {
                Text("Playlists").tag(0)
                Text("Albums").tag(1)
                Text("Songs").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            TabView(selection: $selectedTab) {
                PlaylistsTab()
                    .tag(0)

                AlbumsTab()
                    .tag(1)

                SongsTab()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Library")
        .task {
            await musicService.loadLibraryData()
        }
    }
}

// MARK: - Playlists Tab

struct PlaylistsTab: View {
    @ObservedObject var musicService = MusicKitService.shared

    var body: some View {
        List {
            ForEach(musicService.userPlaylists, id: \.id) { playlist in
                PlaylistRow(playlist: playlist)
            }
        }
        .listStyle(.plain)
        .overlay {
            if musicService.userPlaylists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            }
        }
    }
}

// MARK: - Albums Tab

struct AlbumsTab: View {
    @State private var albums: MusicItemCollection<Album> = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            ForEach(albums, id: \.id) { album in
                AlbumRow(album: album)
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Unable to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await loadAlbums() }
                    }
                }
            } else if albums.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Albums you've added will appear here")
                )
            }
        }
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        isLoading = true
        loadError = nil
        do {
            let request = MusicLibraryRequest<Album>()
            let response = try await request.response()
            albums = response.items
        } catch {
            musicLogger.warning("Failed to load albums: \(error.localizedDescription)")
            loadError = "Failed to load albums"
        }
        isLoading = false
    }
}

// MARK: - Songs Tab

struct SongsTab: View {
    @State private var songs: MusicItemCollection<Song> = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            ForEach(songs, id: \.id) { song in
                SongRow(song: song)
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Unable to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await loadSongs() }
                    }
                }
            } else if songs.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Songs you've added will appear here")
                )
            }
        }
        .task {
            await loadSongs()
        }
    }

    private func loadSongs() async {
        isLoading = true
        loadError = nil
        do {
            var request = MusicLibraryRequest<Song>()
            request.limit = 100
            let response = try await request.response()
            songs = response.items
        } catch {
            musicLogger.warning("Failed to load songs: \(error.localizedDescription)")
            loadError = "Failed to load songs"
        }
        isLoading = false
    }
}

#Preview {
    NavigationView {
        MusicLibraryView()
    }
}
