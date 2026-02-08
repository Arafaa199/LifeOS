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
    @State private var searchText = ""

    private var filteredPlaylists: [Playlist] {
        let playlists = Array(musicService.userPlaylists)
        if searchText.isEmpty {
            return playlists
        }
        return playlists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            LazyVStack(spacing: 0) {
                ForEach(filteredPlaylists, id: \.id) { playlist in
                    PlaylistRow(playlist: playlist)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search playlists")
        .overlay {
            if musicService.userPlaylists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            } else if filteredPlaylists.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No playlists match your search")
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
    @State private var searchText = ""

    private var filteredAlbums: [Album] {
        if searchText.isEmpty {
            return albums.map { $0 }
        }
        return albums.filter { album in
            let albumNameMatch = album.title.localizedCaseInsensitiveContains(searchText)
            let artistMatch = album.artistName.localizedCaseInsensitiveContains(searchText)
            return albumNameMatch || artistMatch
        }
    }

    var body: some View {
        List {
            LazyVStack(spacing: 0) {
                ForEach(filteredAlbums, id: \.id) { album in
                    AlbumRow(album: album)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search albums")
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
            } else if filteredAlbums.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No albums match your search")
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
    @State private var searchText = ""

    private var filteredSongs: [Song] {
        if searchText.isEmpty {
            return songs.map { $0 }
        }
        return songs.filter { song in
            let titleMatch = song.title.localizedCaseInsensitiveContains(searchText)
            let artistMatch = song.artistName.localizedCaseInsensitiveContains(searchText)
            let albumMatch = (song.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
            return titleMatch || artistMatch || albumMatch
        }
    }

    var body: some View {
        List {
            LazyVStack(spacing: 0) {
                ForEach(filteredSongs, id: \.id) { song in
                    SongRow(song: song)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search songs")
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
            } else if filteredSongs.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No songs match your search")
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
