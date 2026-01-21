import Foundation

// MARK: - Dashboard Payload DTO
// Matches the JSON structure from GET /webhook/nexus-dashboard-today
// Schema version: 1

struct DashboardPayload: Codable {
    let meta: DashboardMeta
    let todayFacts: TodayFacts
    let trends: [TrendPeriod]
    let feedStatus: [FeedStatus]
    let staleFeeds: [String]
    let recentEvents: [RecentEvent]

    enum CodingKeys: String, CodingKey {
        case meta
        case todayFacts = "today_facts"
        case trends
        case feedStatus = "feed_status"
        case staleFeeds = "stale_feeds"
        case recentEvents = "recent_events"
    }
}

// MARK: - Meta

struct DashboardMeta: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let forDate: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case forDate = "for_date"
        case timezone
    }
}

// MARK: - Today Facts

struct TodayFacts: Codable {
    let day: String
    let recoveryScore: Int?
    let hrv: Double?
    let rhr: Int?
    let sleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let sleepEfficiency: Double?
    let strain: Double?
    let steps: Int?
    let weightKg: Double?
    let spendTotal: Double?
    let spendGroceries: Double?
    let spendRestaurants: Double?
    let incomeTotal: Double?
    let transactionCount: Int?
    let mealsLogged: Int?
    let waterMl: Int?
    let caloriesConsumed: Int?
    let dataCompleteness: Double?
    let factsComputedAt: String?

    // Comparisons vs baselines
    let recoveryVs7d: Double?
    let recoveryVs30d: Double?
    let hrvVs7d: Double?
    let sleepVs7d: Double?
    let strainVs7d: Double?
    let spendVs7d: Double?
    let weightVs7d: Double?

    // Unusual flags
    let recoveryUnusual: Bool?
    let sleepUnusual: Bool?
    let spendUnusual: Bool?

    // 7-day and 30-day averages
    let recovery7dAvg: Double?
    let recovery30dAvg: Double?
    let hrv7dAvg: Double?
    let sleepMinutes7dAvg: Double?
    let weight30dDelta: Double?
    let daysWithData7d: Int?
    let daysWithData30d: Int?
    let baselinesComputedAt: String?

    enum CodingKeys: String, CodingKey {
        case day
        case recoveryScore = "recovery_score"
        case hrv, rhr
        case sleepMinutes = "sleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case strain, steps
        case weightKg = "weight_kg"
        case spendTotal = "spend_total"
        case spendGroceries = "spend_groceries"
        case spendRestaurants = "spend_restaurants"
        case incomeTotal = "income_total"
        case transactionCount = "transaction_count"
        case mealsLogged = "meals_logged"
        case waterMl = "water_ml"
        case caloriesConsumed = "calories_consumed"
        case dataCompleteness = "data_completeness"
        case factsComputedAt = "facts_computed_at"
        case recoveryVs7d = "recovery_vs_7d"
        case recoveryVs30d = "recovery_vs_30d"
        case hrvVs7d = "hrv_vs_7d"
        case sleepVs7d = "sleep_vs_7d"
        case strainVs7d = "strain_vs_7d"
        case spendVs7d = "spend_vs_7d"
        case weightVs7d = "weight_vs_7d"
        case recoveryUnusual = "recovery_unusual"
        case sleepUnusual = "sleep_unusual"
        case spendUnusual = "spend_unusual"
        case recovery7dAvg = "recovery_7d_avg"
        case recovery30dAvg = "recovery_30d_avg"
        case hrv7dAvg = "hrv_7d_avg"
        case sleepMinutes7dAvg = "sleep_minutes_7d_avg"
        case weight30dDelta = "weight_30d_delta"
        case daysWithData7d = "days_with_data_7d"
        case daysWithData30d = "days_with_data_30d"
        case baselinesComputedAt = "baselines_computed_at"
    }

    // MARK: - Computed Properties

    var sleepHours: Double {
        guard let minutes = sleepMinutes else { return 0 }
        return Double(minutes) / 60.0
    }

    var deepSleepHours: Double {
        guard let minutes = deepSleepMinutes else { return 0 }
        return Double(minutes) / 60.0
    }

    var remSleepHours: Double {
        guard let minutes = remSleepMinutes else { return 0 }
        return Double(minutes) / 60.0
    }

    var lightSleepMinutes: Int? {
        guard let total = sleepMinutes, let deep = deepSleepMinutes, let rem = remSleepMinutes else {
            return nil
        }
        return total - deep - rem
    }
}

// MARK: - Trend Period

struct TrendPeriod: Codable, Identifiable {
    var id: String { period }

    let period: String
    let avgRecovery: Double?
    let avgHrv: Double?
    let avgRhr: Double?
    let avgSleepMinutes: Double?
    let avgStrain: Double?
    let avgSteps: Int?
    let totalSpend: Double?
    let avgDailySpend: Double?
    let weightRange: Double?
    let latestWeight: Double?

    enum CodingKeys: String, CodingKey {
        case period
        case avgRecovery = "avg_recovery"
        case avgHrv = "avg_hrv"
        case avgRhr = "avg_rhr"
        case avgSleepMinutes = "avg_sleep_minutes"
        case avgStrain = "avg_strain"
        case avgSteps = "avg_steps"
        case totalSpend = "total_spend"
        case avgDailySpend = "avg_daily_spend"
        case weightRange = "weight_range"
        case latestWeight = "latest_weight"
    }

    var avgSleepHours: Double {
        guard let minutes = avgSleepMinutes else { return 0 }
        return minutes / 60.0
    }
}

// MARK: - Feed Status

struct FeedStatus: Codable, Identifiable {
    var id: String { feed }

    let feed: String
    let status: FeedHealthStatus
    let lastSync: String?
    let totalRecords: Int?
    let hoursSinceSync: Double?

    enum CodingKeys: String, CodingKey {
        case feed, status
        case lastSync = "last_sync"
        case totalRecords = "total_records"
        case hoursSinceSync = "hours_since_sync"
    }
}

enum FeedHealthStatus: String, Codable {
    case healthy
    case stale
    case critical
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FeedHealthStatus(rawValue: rawValue) ?? .unknown
    }
}

// MARK: - Recent Event

struct RecentEvent: Codable, Identifiable {
    var id: String { "\(eventType)-\(eventDate)-\(eventTime)" }

    let eventType: String
    let eventDate: String
    let eventTime: String
    let payload: EventPayload

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventDate = "event_date"
        case eventTime = "event_time"
        case payload
    }
}

struct EventPayload: Codable {
    let amount: Double?
    let category: String?
    let merchant: String?

    // For other event types, add optional fields as needed
    let weightKg: Double?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case amount, category, merchant
        case weightKg = "weight_kg"
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

// MARK: - API Response Wrapper

struct DashboardResponse: Codable {
    let success: Bool?
    let data: DashboardPayload?
    let error: String?

    // Handle both wrapped and unwrapped responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try wrapped format first
        if container.contains(.success) {
            success = try container.decodeIfPresent(Bool.self, forKey: .success)
            data = try container.decodeIfPresent(DashboardPayload.self, forKey: .data)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        } else {
            // Unwrapped format - the response IS the payload
            success = true
            data = try DashboardPayload(from: decoder)
            error = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }
}
