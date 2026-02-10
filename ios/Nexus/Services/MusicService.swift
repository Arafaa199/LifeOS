import Foundation
import Combine
import MediaPlayer
import os

/// Passive Apple Music observer that logs track changes to the backend.
/// - Does not control playback
/// - Observes nowPlayingItem changes
/// - Batches events for sync
@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()
    
    // MARK: - Published State
    
    @Published private(set) var currentTrack: ListeningEvent?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published private(set) var todayEvents: [ListeningEvent] = []
    
    // MARK: - Private State
    
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var currentSessionId: UUID = UUID()
    private var pendingEvents: [ListeningEvent] = []
    private var lastTrackStartTime: Date?
    private var isObserving = false
    
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "music")
    private let sessionGapThreshold: TimeInterval = 300 // 5 minutes
    private let syncBatchSize = 5
    
    // MARK: - Init
    
    private init() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        loadPendingEvents()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        let status = await MPMediaLibrary.requestAuthorization()
        authorizationStatus = status
        return status == .authorized
    }
    
    // MARK: - Observation Control
    
    func startObserving() {
        guard authorizationStatus == .authorized else {
            logger.warning("Cannot start observing: not authorized")
            return
        }
        guard !isObserving else { return }
        
        isObserving = true
        player.beginGeneratingPlaybackNotifications()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemDidChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateDidChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        
        // Capture current state
        updateCurrentTrack()
        isPlaying = player.playbackState == .playing
        
        logger.info("Music observation started")
    }
    
    func stopObserving() {
        guard isObserving else { return }
        
        // End current track if playing
        endCurrentTrackIfNeeded()
        
        NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
        NotificationCenter.default.removeObserver(self, name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
        player.endGeneratingPlaybackNotifications()
        
        isObserving = false
        logger.info("Music observation stopped")
    }
    
    // MARK: - Notification Handlers
    
    @objc private func nowPlayingItemDidChange(_ notification: Notification) {
        Task { @MainActor in
            endCurrentTrackIfNeeded()
            checkSessionGap()
            updateCurrentTrack()
        }
    }
    
    @objc private func playbackStateDidChange(_ notification: Notification) {
        Task { @MainActor in
            let newState = player.playbackState
            let wasPlaying = isPlaying
            isPlaying = newState == .playing
            
            if wasPlaying && !isPlaying {
                // Stopped playing - end current track
                endCurrentTrackIfNeeded()
            } else if !wasPlaying && isPlaying {
                // Started playing - check for session gap, capture track
                checkSessionGap()
                if currentTrack == nil {
                    updateCurrentTrack()
                }
            }
        }
    }
    
    // MARK: - Track Management
    
    private func updateCurrentTrack() {
        guard let item = player.nowPlayingItem else {
            currentTrack = nil
            lastTrackStartTime = nil
            return
        }
        
        let now = Date()
        lastTrackStartTime = now
        
        let event = ListeningEvent(
            sessionId: currentSessionId.uuidString,
            trackTitle: item.title ?? "Unknown Track",
            artist: item.artist,
            album: item.albumTitle,
            durationSec: Int(item.playbackDuration),
            appleMusicId: String(item.persistentID),
            startedAt: iso8601String(from: now)
        )
        
        currentTrack = event
        logger.debug("Now playing: \(event.trackTitle) by \(event.artist ?? "Unknown")")
    }
    
    private func endCurrentTrackIfNeeded() {
        guard var event = currentTrack else { return }
        
        let now = Date()
        event.endedAt = iso8601String(from: now)
        
        // Only log if played for at least 10 seconds
        if let startTime = lastTrackStartTime, now.timeIntervalSince(startTime) >= 10 {
            pendingEvents.append(event)
            savePendingEvents()
            logger.debug("Track ended: \(event.trackTitle) (queued, \(self.pendingEvents.count) pending)")
            
            // Sync if batch size reached
            if pendingEvents.count >= syncBatchSize {
                Task { await syncPendingEvents() }
            }
        }
        
        currentTrack = nil
        lastTrackStartTime = nil
    }
    
    private func checkSessionGap() {
        guard let lastStart = lastTrackStartTime else {
            // No previous track, keep current session
            return
        }
        
        let gap = Date().timeIntervalSince(lastStart)
        if gap > sessionGapThreshold {
            currentSessionId = UUID()
            logger.debug("New session started (gap: \(Int(gap))s)")
        }
    }
    
    // MARK: - Sync
    
    func syncPendingEvents() async {
        guard !pendingEvents.isEmpty else { return }
        
        let eventsToSync = pendingEvents
        logger.info("Syncing \(eventsToSync.count) music events")
        
        do {
            let response = try await NexusAPI.shared.logMusicEvents(eventsToSync)
            if response.success {
                // Remove synced events (uses Equatable: sessionId + startedAt)
                pendingEvents.removeAll { event in
                    eventsToSync.contains(event)
                }
                savePendingEvents()
                logger.info("Music events synced successfully")
                
                // Refresh today's events
                await fetchTodayEvents()
            } else {
                logger.error("Music sync failed: \(response.error ?? "unknown")")
            }
        } catch {
            logger.error("Music sync error: \(error.localizedDescription)")
        }
    }
    
    func fetchTodayEvents() async {
        do {
            let response = try await NexusAPI.shared.fetchMusicHistory(limit: 50)
            if response.success {
                // Filter to today only (Dubai timezone)
                let todayString = dubaiDateString(from: Date())
                todayEvents = response.events.filter { $0.startedAt.hasPrefix(todayString) }
                logger.debug("Fetched \(self.todayEvents.count) events for today")
            }
        } catch {
            logger.error("Failed to fetch music history: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Persistence
    
    private func loadPendingEvents() {
        guard let data = UserDefaults.standard.data(forKey: ListeningEvent.pendingEventsKey),
              let events = try? JSONDecoder().decode([ListeningEvent].self, from: data) else {
            return
        }
        pendingEvents = events
        logger.debug("Loaded \(events.count) pending music events")
    }
    
    private func savePendingEvents() {
        guard let data = try? JSONEncoder().encode(pendingEvents) else { return }
        UserDefaults.standard.set(data, forKey: ListeningEvent.pendingEventsKey)
    }
    
    // MARK: - Helpers
    
    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Dubai")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
    
    private func dubaiDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Dubai")
        return formatter.string(from: date)
    }
    
    // MARK: - Playback Controls

    func play() {
        player.play()
        logger.debug("Playback: play")
    }

    func pause() {
        player.pause()
        logger.debug("Playback: pause")
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func skipToNext() {
        player.skipToNextItem()
        logger.debug("Playback: next")
    }

    func skipToPrevious() {
        player.skipToPreviousItem()
        logger.debug("Playback: previous")
    }

    // MARK: - Computed

    var pendingCount: Int { pendingEvents.count }
    var hasAuthorization: Bool { authorizationStatus == .authorized }

    // MARK: - Cleanup

    deinit {
        // Remove NotificationCenter observers to prevent retain cycles
        NotificationCenter.default.removeObserver(self)
        player.endGeneratingPlaybackNotifications()
    }
}
