import SwiftUI
import MusicKit

/// Search Apple Music catalog
struct MusicSearchView: View {
    @ObservedObject var musicService = MusicKitService.shared
    @State private var searchText = ""
    @State private var searchResults: MusicCatalogSearchResponse?
    @State private var isSearching = false

    var body: some View {
        List {
            if isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let results = searchResults {
                if !results.songs.isEmpty {
                    Section("Songs") {
                        ForEach(results.songs.prefix(5), id: \.id) { song in
                            SongRow(song: song)
                        }
                    }
                }

                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums.prefix(5), id: \.id) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                AlbumRow(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists.prefix(5), id: \.id) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                                ArtistRow(artist: artist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !results.playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(results.playlists.prefix(5), id: \.id) { playlist in
                            PlaylistRow(playlist: playlist)
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
            } else {
                Text("Search Apple Music")
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Artists, songs, albums...")
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
        .navigationTitle("Search")
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = nil
            return
        }

        isSearching = true
        Task {
            searchResults = await musicService.search(term: query)
            isSearching = false
        }
    }
}

// MARK: - Row Views

struct SongRow: View {
    let song: Song
    @ObservedObject var musicService = MusicKitService.shared

    var body: some View {
        Button {
            Task { await musicService.playSong(song) }
        } label: {
            HStack(spacing: 12) {
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 48, height: 48)
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Menu {
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
        }
        .buttonStyle(.plain)
    }
}

struct AlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 56, height: 56)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(album.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = artist.artwork {
                ArtworkImage(artwork, width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                    )
            }

            Text(artist.name)
                .font(.subheadline)

            Spacer()
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    @ObservedObject var musicService = MusicKitService.shared

    var body: some View {
        Button {
            Task { await musicService.playPlaylist(playlist) }
        } label: {
            HStack(spacing: 12) {
                if let artwork = playlist.artwork {
                    ArtworkImage(artwork, width: 56, height: 56)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let curator = playlist.curatorName {
                        Text(curator)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationView {
        MusicSearchView()
    }
}
