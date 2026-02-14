import Foundation

// MARK: - BJJ Session Model

struct BJJSession: Codable, Identifiable, Hashable {
    static func == (lhs: BJJSession, rhs: BJJSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: Int
    let sessionDate: String
    let sessionType: String
    let durationMinutes: Int
    let startTime: String?
    let endTime: String?
    let strain: Double?
    let hrAvg: Int?
    let calories: Int?
    let source: String
    let techniques: [String]?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, source, techniques, notes
        case sessionDate = "session_date"
        case sessionType = "session_type"
        case durationMinutes = "duration_minutes"
        case startTime = "start_time"
        case endTime = "end_time"
        case strain
        case hrAvg = "hr_avg"
        case calories
        case createdAt = "created_at"
    }

    var displayDuration: String {
        if durationMinutes >= 60 {
            return "\(durationMinutes / 60)h \(durationMinutes % 60)m"
        }
        return "\(durationMinutes) min"
    }

    var typeDisplayName: String {
        switch sessionType.lowercased() {
        case "bjj": return "BJJ (Gi)"
        case "nogi": return "No-Gi"
        case "mma": return "MMA"
        default: return sessionType.uppercased()
        }
    }

    var typeIcon: String {
        switch sessionType.lowercased() {
        case "bjj", "nogi": return "figure.martial.arts"
        case "mma": return "figure.boxing"
        default: return "figure.martial.arts"
        }
    }

    var sourceIcon: String {
        switch source.lowercased() {
        case "manual": return "hand.tap.fill"
        case "auto_location": return "location.fill"
        case "auto_whoop": return "heart.circle.fill"
        case "notification": return "bell.fill"
        default: return "square.and.arrow.down"
        }
    }

    var sourceDisplayName: String {
        switch source.lowercased() {
        case "manual": return "Manual"
        case "auto_location": return "Location"
        case "auto_whoop": return "Whoop"
        case "notification": return "Notification"
        default: return source
        }
    }
}

// MARK: - Streak Info

struct BJJStreakInfo: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let totalSessions: Int
    let sessionsThisMonth: Int
    let sessionsThisWeek: Int

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalSessions = "total_sessions"
        case sessionsThisMonth = "sessions_this_month"
        case sessionsThisWeek = "sessions_this_week"
    }
}

// MARK: - API Responses

struct BJJHistoryResponse: Codable {
    let success: Bool
    let sessions: [BJJSession]
    let count: Int
    let total: Int
    let streak: BJJStreakInfo
}

struct BJJStreakResponse: Codable {
    let success: Bool
    let currentStreak: Int
    let longestStreak: Int
    let totalSessions: Int
    let sessionsThisMonth: Int
    let sessionsThisWeek: Int

    enum CodingKeys: String, CodingKey {
        case success
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalSessions = "total_sessions"
        case sessionsThisMonth = "sessions_this_month"
        case sessionsThisWeek = "sessions_this_week"
    }

    var streakInfo: BJJStreakInfo {
        BJJStreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalSessions: totalSessions,
            sessionsThisMonth: sessionsThisMonth,
            sessionsThisWeek: sessionsThisWeek
        )
    }
}

struct BJJLogResponse: Codable {
    let success: Bool
    let session: BJJSession
    let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case success, session
        case isNew = "is_new"
    }
}

// MARK: - Request Models

struct LogBJJRequest: Codable {
    let sessionDate: String
    let sessionType: String
    let durationMinutes: Int
    let startTime: String?
    let endTime: String?
    let strain: Double?
    let hrAvg: Int?
    let calories: Int?
    let techniques: [String]?
    let notes: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case source, techniques, notes, strain, calories
        case sessionDate = "session_date"
        case sessionType = "session_type"
        case durationMinutes = "duration_minutes"
        case startTime = "start_time"
        case endTime = "end_time"
        case hrAvg = "hr_avg"
    }

    init(
        sessionDate: String,
        sessionType: String = "bjj",
        durationMinutes: Int = 60,
        startTime: String? = nil,
        endTime: String? = nil,
        strain: Double? = nil,
        hrAvg: Int? = nil,
        calories: Int? = nil,
        techniques: [String]? = nil,
        notes: String? = nil,
        source: String = "manual"
    ) {
        self.sessionDate = sessionDate
        self.sessionType = sessionType
        self.durationMinutes = durationMinutes
        self.startTime = startTime
        self.endTime = endTime
        self.strain = strain
        self.hrAvg = hrAvg
        self.calories = calories
        self.techniques = techniques
        self.notes = notes
        self.source = source
    }
}

struct BJJDeleteResponse: Codable {
    let success: Bool
    let deleted: DeletedSession?

    struct DeletedSession: Codable {
        let id: Int
        let sessionDate: String?

        enum CodingKeys: String, CodingKey {
            case id
            case sessionDate = "session_date"
        }
    }
}

struct BJJUpdateRequest: Codable {
    let id: Int
    let sessionDate: String?
    let sessionType: String?
    let durationMinutes: Int?
    let techniques: [String]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, techniques, notes
        case sessionDate = "session_date"
        case sessionType = "session_type"
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Session Type Enum

enum BJJSessionType: String, CaseIterable {
    case bjj = "bjj"
    case nogi = "nogi"
    case mma = "mma"

    var displayName: String {
        switch self {
        case .bjj: return "BJJ (Gi)"
        case .nogi: return "No-Gi"
        case .mma: return "MMA"
        }
    }

    var icon: String {
        switch self {
        case .bjj, .nogi: return "figure.martial.arts"
        case .mma: return "figure.boxing"
        }
    }
}
