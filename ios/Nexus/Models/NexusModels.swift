import Foundation

// MARK: - API Request/Response Models

struct FoodLogRequest: Codable {
    let text: String
    let source: String = "ios"
}

struct WaterLogRequest: Codable {
    let amount_ml: Int
}

struct WeightLogRequest: Codable {
    let weight_kg: Double
}

struct MoodLogRequest: Codable {
    let mood: Int
    let energy: Int
    let notes: String?
}

struct UniversalLogRequest: Codable {
    let text: String
    let source: String = "ios"
    let context: String = "auto"
}

struct NexusResponse: Codable {
    let success: Bool
    let message: String?
    let data: ResponseData?
}

struct ResponseData: Codable {
    let calories: Int?
    let protein: Double?
    let total_water_ml: Int?
    let weight_kg: Double?
}

// MARK: - Sync Status

struct SyncStatusResponse: Codable {
    let success: Bool
    let domains: [SyncDomainStatus]?
    let timestamp: String?
}

struct SyncDomainStatus: Codable, Identifiable {
    var id: String { domain }
    let domain: String
    let last_success_at: String?
    let last_success_rows: Int?
    let last_success_duration_ms: Int?
    let last_success_source: String?
    let last_error_at: String?
    let last_error: String?
    let running_count: Int?
    let freshness: String?
    let seconds_since_success: Int?
}

// MARK: - View Models

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let description: String
    let calories: Int?
    let protein: Double?
}

enum LogType: String, CaseIterable {
    case food = "Food"
    case water = "Water"
    case weight = "Weight"
    case mood = "Mood"
    case note = "Note"
    case other = "Other"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .water: return "drop.fill"
        case .weight: return "scalemass.fill"
        case .mood: return "face.smiling.fill"
        case .note: return "note.text"
        case .other: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .food: return "orange"
        case .water: return "blue"
        case .weight: return "green"
        case .mood: return "purple"
        case .note: return "gray"
        case .other: return "secondary"
        }
    }
}

struct DailySummary {
    var totalCalories: Int = 0
    var totalProtein: Double = 0
    var totalWater: Int = 0
    var latestWeight: Double?
    var weight: Double? // Alias for latestWeight
    var mood: Int?
    var energy: Int?
}
