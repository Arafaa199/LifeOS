import Foundation
import MusicKit
import MediaPlayer
import Combine
import os

/// Full MusicKit integration service for Apple Music playback and library access
@MainActor
final class MusicKitService: ObservableObject {
    static let shared = MusicKitService()

    // MARK: - Published State

    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentEntry: ApplicationMusicPlayer.Queue.Entry?
    @Published private(set) var queue: [ApplicationMusicPlayer.Queue.Entry] = []
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var shuffleMode: MusicKit.MusicPlayer.ShuffleMode = .off
    @Published private(set) var repeatMode: MusicKit.MusicPlayer.RepeatMode = .none
    @Published private(set) var artwork: Artwork?
    @Published private(set) var recentlyPlayed: MusicItemCollection<RecentlyPlayedMusicItem> = []
    @Published private(set) var userPlaylists: MusicItemCollection<Playlist> = []

    // MARK: - Player

    private let player = ApplicationMusicPlayer.shared
    private var stateObserver: AnyCancellable?
    private var queueObserver: AnyCancellable?
    private var playbackTimeTimer: Timer?
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "musickit")

    // MARK: - Init

    private init() {
        Task {
            authorizationStatus = MusicAuthorization.currentStatus
            if authorizationStatus == .authorized {
                setupObservers()
                await loadLibraryData()
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        authorizationStatus = status

        if status == .authorized {
            setupObservers()
            await loadLibraryData()
        }

        return status == .authorized
    }

    var isAuthorized: Bool { authorizationStatus == .authorized }

    // MARK: - Observers

    private func setupObservers() {
        // Playback state observer
        stateObserver = player.state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updatePlaybackState()
                }
            }

        // Queue observer
        queueObserver = player.queue.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateQueue()
                }
            }

        // Initial state
        updatePlaybackState()
        updateQueue()
        startPlaybackTimeUpdates()
    }

    private func updatePlaybackState() {
        isPlaying = player.state.playbackStatus == .playing
        currentEntry = player.queue.currentEntry
        artwork = currentEntry?.artwork

        if let item = currentEntry?.item {
            if case let .song(song) = item {
                duration = song.duration ?? 0
            }
        }
    }

    private func updateQueue() {
        queue = Array(player.queue.entries)
        currentEntry = player.queue.currentEntry
    }

    private func startPlaybackTimeUpdates() {
        playbackTimeTimer?.invalidate()
        playbackTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playbackTime = self?.player.playbackTime ?? 0
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        Task {
            do {
                try await player.play()
                // Restart the playback time timer
                startPlaybackTimeUpdates()
                logger.debug("Playback started")
            } catch {
                logger.error("Failed to play: \(error.localizedDescription)")
            }
        }
    }

    func pause() {
        player.pause()
        // Stop the playback time timer when paused to avoid unnecessary updates
        playbackTimeTimer?.invalidate()
        playbackTimeTimer = nil
        logger.debug("Playback paused")
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func skipToNext() {
        Task {
            do {
                try await player.skipToNextEntry()
                logger.debug("Skipped to next")
            } catch {
                logger.error("Failed to skip: \(error.localizedDescription)")
            }
        }
    }

    func skipToPrevious() {
        Task {
            do {
                try await player.skipToPreviousEntry()
                logger.debug("Skipped to previous")
            } catch {
                logger.error("Failed to skip back: \(error.localizedDescription)")
            }
        }
    }

    func restartOrPrevious() {
        // If more than 3 seconds in, restart; otherwise go to previous
        if playbackTime > 3 {
            seek(to: 0)
        } else {
            skipToPrevious()
        }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = time
        playbackTime = time
    }

    func toggleShuffle() {
        let newMode: MusicKit.MusicPlayer.ShuffleMode = shuffleMode == .off ? .songs : .off
        player.state.shuffleMode = newMode
        shuffleMode = newMode
        logger.debug("Shuffle: \(newMode == .songs ? "on" : "off")")
    }

    func toggleRepeat() {
        cycleRepeatMode()
    }

    func cycleRepeatMode() {
        let newMode: MusicKit.MusicPlayer.RepeatMode
        switch repeatMode {
        case .none: newMode = .all
        case .all: newMode = .one
        case .one: newMode = .none
        @unknown default: newMode = .none
        }
        player.state.repeatMode = newMode
        repeatMode = newMode
        logger.debug("Repeat: \(String(describing: newMode))")
    }

    func clearQueue() {
        Task {
            player.queue = []
            queue = []
            currentEntry = nil
            logger.debug("Queue cleared")
        }
    }

    // MARK: - Queue Management

    func playSong(_ song: Song) async {
        do {
            player.queue = [song]
            try await player.play()
            logger.info("Playing song: \(song.title)")
        } catch {
            logger.error("Failed to play song: \(error.localizedDescription)")
        }
    }

    func playSongs(_ songs: [Song], shuffle: Bool = false) async {
        guard !songs.isEmpty else { return }
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            if shuffle {
                player.state.shuffleMode = .songs
                shuffleMode = .songs
            }
            try await player.play()
            logger.info("Playing \(songs.count) songs (shuffle: \(shuffle))")
        } catch {
            logger.error("Failed to play songs: \(error.localizedDescription)")
        }
    }

    func playAlbum(_ album: Album, shuffle: Bool = false) async {
        do {
            let detailedAlbum = try await album.with([.tracks])
            if let tracks = detailedAlbum.tracks {
                player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                if shuffle {
                    player.state.shuffleMode = .songs
                    shuffleMode = .songs
                }
                try await player.play()
                logger.info("Playing album: \(album.title) (shuffle: \(shuffle))")
            }
        } catch {
            logger.error("Failed to play album: \(error.localizedDescription)")
        }
    }

    func playPlaylist(_ playlist: Playlist) async {
        do {
            let detailedPlaylist = try await playlist.with([.tracks])
            if let tracks = detailedPlaylist.tracks {
                player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                try await player.play()
                logger.info("Playing playlist: \(playlist.name)")
            }
        } catch {
            logger.error("Failed to play playlist: \(error.localizedDescription)")
        }
    }

    func addToQueue(_ song: Song) async {
        do {
            try await player.queue.insert(song, position: .tail)
            logger.debug("Added to queue: \(song.title)")
        } catch {
            logger.error("Failed to add to queue: \(error.localizedDescription)")
        }
    }

    func playNext(_ song: Song) async {
        do {
            try await player.queue.insert(song, position: .afterCurrentEntry)
            logger.debug("Play next: \(song.title)")
        } catch {
            logger.error("Failed to play next: \(error.localizedDescription)")
        }
    }

    // MARK: - Library Data

    func loadLibraryData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRecentlyPlayed() }
            group.addTask { await self.loadUserPlaylists() }
        }
    }

    func loadRecentlyPlayed() async {
        do {
            let request = MusicRecentlyPlayedRequest<Song>()
            let response = try await request.response()
            // Convert to RecentlyPlayedMusicItem - this is a simplified approach
            logger.debug("Loaded recently played")
        } catch {
            logger.error("Failed to load recently played: \(error.localizedDescription)")
        }
    }

    func loadUserPlaylists() async {
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            userPlaylists = response.items
            logger.debug("Loaded \(response.items.count) playlists")
        } catch {
            logger.error("Failed to load playlists: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    func search(term: String) async -> MusicCatalogSearchResponse? {
        guard !term.isEmpty else { return nil }

        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self, Playlist.self])
            request.limit = 25
            let response = try await request.response()
            logger.debug("Search results: \(response.songs.count) songs, \(response.albums.count) albums")
            return response
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Current Track Info

    var currentSong: Song? {
        guard let entry = currentEntry, case let .song(song) = entry.item else {
            return nil
        }
        return song
    }

    var currentTitle: String {
        currentSong?.title ?? "Not Playing"
    }

    var currentArtist: String {
        currentSong?.artistName ?? ""
    }

    var currentAlbum: String {
        currentSong?.albumTitle ?? ""
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return playbackTime / duration
    }

    // MARK: - Cleanup

    deinit {
        playbackTimeTimer?.invalidate()
    }
}

// MARK: - Time Formatting

extension MusicKitService {
    func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
