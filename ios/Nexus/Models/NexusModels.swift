import Foundation

// MARK: - API Request/Response Models

struct FoodLogRequest: Codable, Sendable {
    let text: String
    let source: String = "ios"
    let food_id: Int?
    let meal_type: String?

    init(text: String, food_id: Int? = nil, meal_type: String? = nil) {
        self.text = text
        self.food_id = food_id
        self.meal_type = meal_type
    }
}

struct FoodSearchResult: Codable, Identifiable, Sendable {
    let id: Int
    let fdc_id: Int?
    let barcode: String?
    let name: String
    let brand: String?
    let source: String?
    let calories_per_100g: Double?
    let protein_per_100g: Double?
    let carbs_per_100g: Double?
    let fat_per_100g: Double?
    let fiber_per_100g: Double?
    let serving_size_g: Double?
    let serving_description: String?
    let category: String?
    let data_quality: Int?
    let relevance: Double?

    // Custom decoder to handle API returning strings for numeric fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        fdc_id = try container.decodeIfPresent(Int.self, forKey: .fdc_id)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        calories_per_100g = Self.decodeFlexibleDouble(container, forKey: .calories_per_100g)
        protein_per_100g = Self.decodeFlexibleDouble(container, forKey: .protein_per_100g)
        carbs_per_100g = Self.decodeFlexibleDouble(container, forKey: .carbs_per_100g)
        fat_per_100g = Self.decodeFlexibleDouble(container, forKey: .fat_per_100g)
        fiber_per_100g = Self.decodeFlexibleDouble(container, forKey: .fiber_per_100g)
        serving_size_g = Self.decodeFlexibleDouble(container, forKey: .serving_size_g)
        serving_description = try container.decodeIfPresent(String.self, forKey: .serving_description)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        data_quality = try container.decodeIfPresent(Int.self, forKey: .data_quality)
        relevance = Self.decodeFlexibleDouble(container, forKey: .relevance)
    }

    private static func decodeFlexibleDouble(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, fdc_id, barcode, name, brand, source
        case calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g
        case serving_size_g, serving_description, category, data_quality, relevance
    }
}

struct FoodSearchResponse: Codable, Sendable {
    let success: Bool
    let count: Int?
    let data: [FoodSearchResult]?
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

// MARK: - Nutrition History Models

struct NutritionHistoryResponse: Codable, Sendable {
    let success: Bool
    let date: String
    let food_log: [FoodLogEntry]
    let water_log: [WaterLogEntry]
    let totals: NutritionTotals
}

struct FoodLogEntry: Codable, Identifiable, Sendable {
    let id: Int
    let description: String?
    let meal_time: String?
    let calories: Int?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
    let source: String?
    let confidence: String?
    let logged_at: String?

    var mealTypeDisplay: String {
        guard let mealTime = meal_time else { return "Snack" }
        return mealTime.capitalized
    }

    var sourceIcon: String {
        guard let source = source?.lowercased() else { return "pencil" }
        if source.contains("voice") { return "mic.fill" }
        if source.contains("photo") { return "camera.fill" }
        if source.contains("barcode") { return "barcode.viewfinder" }
        return "pencil"
    }

    var formattedTime: String {
        guard let loggedAt = logged_at else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: loggedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        // Try without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: loggedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        return ""
    }
}

struct WaterLogEntry: Codable, Identifiable, Sendable {
    let id: Int
    let amount_ml: Int
    let logged_at: String?

    var formattedTime: String {
        guard let loggedAt = logged_at else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: loggedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: loggedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        return ""
    }
}

struct NutritionTotals: Codable, Sendable {
    let calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let water_ml: Int
    let meals_logged: Int
}

// MARK: - Water Log Response

struct WaterLogResponse: Codable, Sendable {
    let success: Bool
    let data: WaterLogData?
}

struct WaterLogData: Codable, Sendable {
    let id: Int?
    let amount_ml: Int?
    let total_water_ml: Int?
}

// MARK: - Fasting Response

struct FastingResponse: Codable, Sendable {
    let success: Bool?
    let sessionId: Int?
    let startedAt: String?
    let durationHours: Double?
    let isActive: Bool?
    let elapsedHours: Double?
    let error: String?

    // Handle nested result from Postgres function
    let result: FastingResult?

    enum CodingKeys: String, CodingKey {
        case success
        case sessionId = "session_id"
        case startedAt = "started_at"
        case durationHours = "duration_hours"
        case isActive = "is_active"
        case elapsedHours = "elapsed_hours"
        case error
        case result
    }

    // Convenience to get values from either top-level or result
    nonisolated var effectiveSuccess: Bool { success ?? result?.success ?? false }
    nonisolated var effectiveSessionId: Int? { sessionId ?? result?.sessionId }
    nonisolated var effectiveElapsedHours: Double? { elapsedHours ?? result?.elapsedHours }
    nonisolated var effectiveDurationHours: Double? { durationHours ?? result?.durationHours }
}

struct FastingResult: Codable, Sendable {
    let success: Bool?
    let sessionId: Int?
    let startedAt: String?
    let durationHours: Double?
    let isActive: Bool?
    let elapsedHours: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case sessionId = "session_id"
        case startedAt = "started_at"
        case durationHours = "duration_hours"
        case isActive = "is_active"
        case elapsedHours = "elapsed_hours"
        case error
    }
}

