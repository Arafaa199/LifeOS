import Foundation

// MARK: - Health Dashboard DTO
// Single endpoint: GET /app/health
// Returns everything needed for the Health tab in one call

struct HealthDashboardDTO: Codable {
    let meta: HealthMeta
    let today: HealthTodayDTO
    let trends: HealthTrendsDTO
    let insight: HealthInsightDTO?

    enum CodingKeys: String, CodingKey {
        case meta, today, trends, insight
    }
}

struct HealthMeta: Codable {
    let generatedAt: Date
    let timezone: String
    let dataCompleteness: Double  // 0-1, how much data is available

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone
        case dataCompleteness = "data_completeness"
    }
}

// MARK: - Today Section

struct HealthTodayDTO: Codable {
    // Recovery (WHOOP)
    let recoveryScore: Int?
    let recoveryVs7d: Double?      // Percentage change vs 7-day avg
    let isRecoveryUnusual: Bool

    // HRV & Heart
    let hrv: Double?               // ms
    let hrvVs7d: Double?
    let rhr: Int?                  // bpm

    // Sleep
    let sleepMinutes: Int?
    let sleepEfficiency: Double?   // 0-100
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let sleepVs7d: Double?
    let isSleepUnusual: Bool

    // Activity
    let strain: Double?
    let steps: Int?

    // Body
    let weightKg: Double?
    let weightVs7d: Double?        // kg change
    let weight30dDelta: Double?    // kg change over 30 days

    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case recoveryVs7d = "recovery_vs_7d"
        case isRecoveryUnusual = "is_recovery_unusual"
        case hrv
        case hrvVs7d = "hrv_vs_7d"
        case rhr
        case sleepMinutes = "sleep_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case sleepVs7d = "sleep_vs_7d"
        case isSleepUnusual = "is_sleep_unusual"
        case strain, steps
        case weightKg = "weight_kg"
        case weightVs7d = "weight_vs_7d"
        case weight30dDelta = "weight_30d_delta"
    }

    // Computed
    var sleepHours: Double {
        guard let minutes = sleepMinutes else { return 0 }
        return Double(minutes) / 60.0
    }

    var lightSleepMinutes: Int? {
        guard let total = sleepMinutes, let deep = deepSleepMinutes, let rem = remSleepMinutes else {
            return nil
        }
        return max(0, total - deep - rem)
    }
}

// MARK: - Trends Section

struct HealthTrendsDTO: Codable {
    let recovery7d: [Int?]         // Last 7 days recovery scores
    let sleep7d: [Double?]         // Last 7 days sleep hours
    let weight7d: [Double?]        // Last 7 days weight

    let avg7dRecovery: Double?
    let avg7dSleep: Double?
    let avg7dHrv: Double?

    enum CodingKeys: String, CodingKey {
        case recovery7d = "recovery_7d"
        case sleep7d = "sleep_7d"
        case weight7d = "weight_7d"
        case avg7dRecovery = "avg_7d_recovery"
        case avg7dSleep = "avg_7d_sleep"
        case avg7dHrv = "avg_7d_hrv"
    }
}

// MARK: - Insight

struct HealthInsightDTO: Codable, Identifiable {
    var id: String { type }

    let type: String
    let title: String
    let detail: String
    let icon: String
    let confidence: InsightConfidence
    let color: String              // "green", "orange", "red", "blue", "purple"

    enum InsightConfidence: String, Codable {
        case early
        case moderate
        case strong
    }
}

// MARK: - API Response Wrapper

struct HealthDashboardResponse: Codable {
    let success: Bool
    let data: HealthDashboardDTO?
    let error: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.success) {
            success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
            data = try container.decodeIfPresent(HealthDashboardDTO.self, forKey: .data)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        } else {
            success = true
            data = try HealthDashboardDTO(from: decoder)
            error = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }
}

// MARK: - Preview Fixtures

extension HealthDashboardDTO {
    static let preview: HealthDashboardDTO = {
        HealthDashboardDTO(
            meta: HealthMeta(
                generatedAt: Date(),
                timezone: "Asia/Dubai",
                dataCompleteness: 0.85
            ),
            today: HealthTodayDTO(
                recoveryScore: 72,
                recoveryVs7d: 8.5,
                isRecoveryUnusual: false,
                hrv: 48,
                hrvVs7d: 12.3,
                rhr: 58,
                sleepMinutes: 432,  // 7h 12m
                sleepEfficiency: 89,
                deepSleepMinutes: 95,
                remSleepMinutes: 82,
                sleepVs7d: -5.2,
                isSleepUnusual: false,
                strain: 12.4,
                steps: 8_450,
                weightKg: 78.5,
                weightVs7d: -0.3,
                weight30dDelta: -1.2
            ),
            trends: HealthTrendsDTO(
                recovery7d: [65, 72, 58, 80, 75, 82, 72],
                sleep7d: [7.2, 6.8, 7.5, 6.5, 7.8, 7.0, 7.2],
                weight7d: [79.0, 78.8, 78.6, 78.5, 78.7, 78.4, 78.5],
                avg7dRecovery: 72.0,
                avg7dSleep: 7.1,
                avg7dHrv: 45.0
            ),
            insight: HealthInsightDTO(
                type: "recovery_up",
                title: "Recovery trending up",
                detail: "Your HRV is 12% above your 7-day average. Good sleep pays off.",
                icon: "heart.fill",
                confidence: .moderate,
                color: "green"
            )
        )
    }()

    static let lowRecovery: HealthDashboardDTO = {
        HealthDashboardDTO(
            meta: HealthMeta(
                generatedAt: Date(),
                timezone: "Asia/Dubai",
                dataCompleteness: 0.90
            ),
            today: HealthTodayDTO(
                recoveryScore: 32,
                recoveryVs7d: -28.0,
                isRecoveryUnusual: true,
                hrv: 28,
                hrvVs7d: -22.0,
                rhr: 68,
                sleepMinutes: 320,  // 5h 20m
                sleepEfficiency: 72,
                deepSleepMinutes: 45,
                remSleepMinutes: 38,
                sleepVs7d: -25.0,
                isSleepUnusual: true,
                strain: 8.2,
                steps: 4_200,
                weightKg: 78.8,
                weightVs7d: 0.3,
                weight30dDelta: -0.8
            ),
            trends: HealthTrendsDTO(
                recovery7d: [65, 58, 45, 52, 48, 38, 32],
                sleep7d: [7.2, 6.5, 5.8, 6.0, 5.5, 5.8, 5.3],
                weight7d: [78.5, 78.6, 78.7, 78.7, 78.8, 78.8, 78.8],
                avg7dRecovery: 48.0,
                avg7dSleep: 6.0,
                avg7dHrv: 38.0
            ),
            insight: HealthInsightDTO(
                type: "recovery_low",
                title: "Recovery is low today",
                detail: "Consider taking it easy. Low recovery often leads to impulsive decisions.",
                icon: "exclamationmark.triangle",
                confidence: .moderate,
                color: "orange"
            )
        )
    }()

    static let empty: HealthDashboardDTO = {
        HealthDashboardDTO(
            meta: HealthMeta(
                generatedAt: Date(),
                timezone: "Asia/Dubai",
                dataCompleteness: 0.0
            ),
            today: HealthTodayDTO(
                recoveryScore: nil,
                recoveryVs7d: nil,
                isRecoveryUnusual: false,
                hrv: nil,
                hrvVs7d: nil,
                rhr: nil,
                sleepMinutes: nil,
                sleepEfficiency: nil,
                deepSleepMinutes: nil,
                remSleepMinutes: nil,
                sleepVs7d: nil,
                isSleepUnusual: false,
                strain: nil,
                steps: nil,
                weightKg: nil,
                weightVs7d: nil,
                weight30dDelta: nil
            ),
            trends: HealthTrendsDTO(
                recovery7d: [],
                sleep7d: [],
                weight7d: [],
                avg7dRecovery: nil,
                avg7dSleep: nil,
                avg7dHrv: nil
            ),
            insight: nil
        )
    }()
}
