import Foundation

// MARK: - Listening Event

struct ListeningEvent: Codable, Identifiable {
    let id: Int?
    let sessionId: String
    let trackTitle: String
    let artist: String?
    let album: String?
    let durationSec: Int?
    let appleMusicId: String?
    var startedAt: String
    var endedAt: String?
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case id, artist, album, source
        case sessionId = "session_id"
        case trackTitle = "track_title"
        case durationSec = "duration_sec"
        case appleMusicId = "apple_music_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
    
    init(
        id: Int? = nil,
        sessionId: String,
        trackTitle: String,
        artist: String? = nil,
        album: String? = nil,
        durationSec: Int? = nil,
        appleMusicId: String? = nil,
        startedAt: String,
        endedAt: String? = nil,
        source: String = "apple_music"
    ) {
        self.id = id
        self.sessionId = sessionId
        self.trackTitle = trackTitle
        self.artist = artist
        self.album = album
        self.durationSec = durationSec
        self.appleMusicId = appleMusicId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
    }
}

// MARK: - API Request/Response

struct MusicEventsRequest: Codable {
    let events: [ListeningEvent]
}

struct MusicEventsResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}

struct MusicHistoryResponse: Codable {
    let success: Bool
    let events: [ListeningEvent]
    let error: String?
}

// MARK: - Persistence Key

extension ListeningEvent {
    static let pendingEventsKey = "pendingMusicEvents"
}
