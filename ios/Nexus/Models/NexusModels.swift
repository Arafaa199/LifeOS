import Foundation

// MARK: - API Request/Response Models

struct FoodLogRequest: Codable, Sendable {
    let text: String
    let source: String = "ios"
}

struct WaterLogRequest: Codable, Sendable {
    let amount_ml: Int
    
    init(amount_ml: Int) throws {
        guard amount_ml > 0, amount_ml <= 10000 else {
            throw ValidationError.invalidWaterAmount
        }
        self.amount_ml = amount_ml
    }
}

struct WeightLogRequest: Codable, Sendable {
    let weight_kg: Double
    
    init(weight_kg: Double) throws {
        guard weight_kg > 0, weight_kg <= 500 else {
            throw ValidationError.invalidWeight
        }
        self.weight_kg = weight_kg
    }
}

struct MoodLogRequest: Codable, Sendable {
    let mood: Int
    let energy: Int
    let notes: String?
    
    init(mood: Int, energy: Int, notes: String? = nil) throws {
        guard (1...10).contains(mood), (1...10).contains(energy) else {
            throw ValidationError.invalidMoodOrEnergy
        }
        self.mood = mood
        self.energy = energy
        self.notes = notes
    }
}

struct UniversalLogRequest: Codable, Sendable {
    let text: String
    let source: String = "ios"
    let context: String = "auto"
}

struct NexusResponse: Codable, Sendable {
    let success: Bool
    let message: String?
    let data: ResponseData?
}

struct ResponseData: Codable, Sendable {
    let calories: Int?
    let protein: Double?
    let total_water_ml: Int?
    let weight_kg: Double?
}

// MARK: - Sync Status

struct SyncStatusResponse: Codable, Sendable {
    let success: Bool
    let domains: [SyncDomainStatus]?
    let timestamp: String?
}

struct SyncDomainStatus: Codable, Identifiable, Sendable {
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

struct DailySummary: Equatable {
    var totalCalories: Int = 0
    var totalProtein: Double = 0
    var totalWater: Int = 0
    var latestWeight: Double?
    var mood: Int?
    var energy: Int?
    
    // Computed property for backward compatibility
    var weight: Double? {
        get { latestWeight }
        set { latestWeight = newValue }
    }
}
// MARK: - Validation Errors

enum ValidationError: LocalizedError {
    case invalidWaterAmount
    case invalidWeight
    case invalidMoodOrEnergy
    
    var errorDescription: String? {
        switch self {
        case .invalidWaterAmount:
            return "Water amount must be between 1 and 10,000 ml"
        case .invalidWeight:
            return "Weight must be between 1 and 500 kg"
        case .invalidMoodOrEnergy:
            return "Mood and energy must be between 1 and 10"
        }
    }
    
    var recoverySuggestion: String? {
        "Please enter a valid value and try again"
    }
}

