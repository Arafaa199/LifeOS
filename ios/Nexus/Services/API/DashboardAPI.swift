import Foundation

// MARK: - Dashboard API Client

/// Handles dashboard, sleep, health timeseries, WHOOP, home automation, and music endpoints
class DashboardAPI: BaseAPIClient {
    static let shared = DashboardAPI()

    private init() {
        super.init(category: "dashboard-api")
    }

    // MARK: - Date Formatter

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = dubaiTimeZone
        return formatter
    }

    // MARK: - Daily Summary

    func fetchDailySummary(for date: Date = Date()) async throws -> DailySummaryResponse {
        let dateString = Self.dateFormatter.string(from: date)
        let path = buildPath("/webhook/nexus-dashboard-today", query: ["date": dateString])
        let response: DashboardResponse = try await get(path)
        guard let payload = response.data else {
            return DailySummaryResponse(success: false, data: nil)
        }
        let facts = payload.todayFacts
        let data = DailySummaryData(
            date: facts?.day ?? dateString,
            calories: facts?.caloriesConsumed ?? 0,
            protein: facts?.proteinG ?? 0,
            water: facts?.waterMl ?? 0,
            weight: facts?.weightKg,
            mood: nil,
            energy: nil,
            logs: nil
        )
        return DailySummaryResponse(success: true, data: data)
    }

    // MARK: - Sleep Data

    func fetchSleepData(for date: Date = Date()) async throws -> SleepResponse {
        let dateString = Self.dateFormatter.string(from: date)
        let path = buildPath("/webhook/nexus-sleep", query: ["date": dateString])
        return try await get(path)
    }

    func fetchSleepHistory(days: Int = 7) async throws -> SleepHistoryResponse {
        let path = buildPath("/webhook/nexus-sleep-history", query: ["days": "\(days)"])
        return try await get(path)
    }

    // MARK: - Health Timeseries

    func fetchHealthTimeseries(days: Int = 30) async throws -> HealthTimeseriesResponse {
        let path = buildPath("/webhook/nexus-health-timeseries", query: ["days": "\(days)"])
        return try await get(path)
    }

    // MARK: - WHOOP Refresh

    func refreshWHOOP() async throws -> WhoopRefreshResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-whoop-refresh", body: EmptyBody(), decoder: JSONDecoder())
    }

    // MARK: - Sync Status

    func fetchSyncStatus() async throws -> SyncStatusResponse {
        return try await get("/webhook/nexus-sync-status")
    }

    // MARK: - Home Assistant

    func fetchHomeStatus() async throws -> HomeStatusResponse {
        return try await get("/webhook/nexus-home-status")
    }

    func controlDevice(entityId: String, action: HomeAction, brightness: Int? = nil) async throws -> HomeControlResponse {
        let request = HomeControlRequest(action: action, entityId: entityId, brightness: brightness)
        return try await post("/webhook/nexus-home-control", body: request)
    }

    // MARK: - Music

    func logMusicEvents(_ events: [ListeningEvent]) async throws -> MusicEventsResponse {
        let request = MusicEventsRequest(events: events)
        return try await post("/webhook/nexus-music-events", body: request)
    }

    func fetchMusicHistory(limit: Int = 20) async throws -> MusicHistoryResponse {
        let path = buildPath("/webhook/nexus-music-history", query: ["limit": "\(limit)"])
        return try await get(path)
    }
}

// MARK: - Response Models

struct DailySummaryResponse: Codable {
    let success: Bool
    let data: DailySummaryData?
}

struct DailySummaryData: Codable {
    let date: String
    let calories: Int
    let protein: Double
    let water: Int
    let weight: Double?
    let mood: Int?
    let energy: Int?
    let logs: [LogEntryData]?
}

struct LogEntryData: Codable {
    let id: String?
    let type: String
    let description: String
    let timestamp: String
    let calories: Int?
    let protein: Double?
}

struct SleepResponse: Codable {
    let success: Bool
    let data: SleepData?
}

struct SleepHistoryResponse: Codable {
    let success: Bool
    let data: [SleepData]?
}

struct SleepData: Codable, Identifiable {
    var id: String { date }
    let date: String
    let sleep: SleepMetrics?
    let recovery: RecoveryMetrics?
}

struct SleepMetrics: Codable {
    let timeInBedMin: Int?
    let awakeMin: Int?
    let lightSleepMin: Int?
    let deepSleepMin: Int?
    let remSleepMin: Int?
    let sleepEfficiency: Double?
    let sleepConsistency: Int?
    let sleepPerformance: Int?
    let sleepNeededMin: Int?
    let sleepDebtMin: Int?
    let cycles: Int?
    let disturbances: Int?
    let respiratoryRate: Double?

    enum CodingKeys: String, CodingKey {
        case timeInBedMin = "time_in_bed_min"
        case awakeMin = "awake_min"
        case lightSleepMin = "light_sleep_min"
        case deepSleepMin = "deep_sleep_min"
        case remSleepMin = "rem_sleep_min"
        case sleepEfficiency = "sleep_efficiency"
        case sleepConsistency = "sleep_consistency"
        case sleepPerformance = "sleep_performance"
        case sleepNeededMin = "sleep_needed_min"
        case sleepDebtMin = "sleep_debt_min"
        case cycles
        case disturbances
        case respiratoryRate = "respiratory_rate"
    }

    var totalSleepMin: Int {
        (lightSleepMin ?? 0) + (deepSleepMin ?? 0) + (remSleepMin ?? 0)
    }
}

struct RecoveryMetrics: Codable {
    let recoveryScore: Int?
    let hrv: Double?
    let rhr: Int?
    let spo2: Double?
    let skinTemp: Double?

    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case hrv = "hrv_rmssd"
        case rhr
        case spo2
        case skinTemp = "skin_temp"
    }
}

struct WhoopRefreshResponse: Codable {
    let success: Bool
    let message: String?
    let sensorsFound: Int?
    let recovery: Double?
    let daily_facts_refreshed: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message, sensorsFound, recovery
        case daily_facts_refreshed
    }
}

struct HealthTimeseriesResponse: Codable {
    let success: Bool
    let data: [DailyHealthPoint]?
    let count: Int?
}

struct DailyHealthPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let hrv: Double?
    let rhr: Int?
    let recovery: Int?
    let sleepMinutes: Int?
    let sleepQuality: Int?
    let strain: Double?
    let steps: Int?
    let weight: Double?
    let activeEnergy: Int?
    let coverage: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case hrv
        case rhr
        case recovery
        case sleepMinutes = "sleep_minutes"
        case sleepQuality = "sleep_quality"
        case strain
        case steps
        case weight
        case activeEnergy = "active_energy"
        case coverage
    }
}
