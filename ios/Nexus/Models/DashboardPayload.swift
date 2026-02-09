import Foundation

// MARK: - Dashboard Payload DTO
// Matches the JSON structure from GET /webhook/nexus-dashboard-today
// Schema version: 1

struct DashboardPayload: Codable {
    let meta: DashboardMeta
    let todayFacts: TodayFacts?
    let trends: [TrendPeriod]
    let feedStatus: [FeedStatus]
    let staleFeeds: [String]
    let recentEvents: [RecentEvent]
    let dailyInsights: DailyInsights?
    let dataFreshness: DataFreshness?
    let domainsStatus: [DomainStatus]?
    let githubActivity: GitHubActivityWidget?
    let calendarSummary: CalendarSummary?
    let reminderSummary: ReminderSummary?
    let fasting: FastingStatus?
    let medicationsToday: MedicationsSummary?
    let streaks: Streaks?
    let musicToday: MusicSummary?
    let moodToday: MoodSummary?
    let explainToday: ExplainToday?

    enum CodingKeys: String, CodingKey {
        case meta
        case todayFacts = "today_facts"
        case trends
        case feedStatus = "feed_status"
        case staleFeeds = "stale_feeds"
        case recentEvents = "recent_events"
        case dailyInsights = "daily_insights"
        case dataFreshness = "data_freshness"
        case domainsStatus = "domains_status"
        case githubActivity = "github_activity"
        case calendarSummary = "calendar_summary"
        case reminderSummary = "reminder_summary"
        case fasting
        case medicationsToday = "medications_today"
        case streaks
        case musicToday = "music_today"
        case moodToday = "mood_today"
        case explainToday = "explain_today"
        // Top-level flat fields (fallback when meta object is missing)
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case targetDate = "target_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle meta: nested object OR flat top-level fields
        if let nestedMeta = try? container.decode(DashboardMeta.self, forKey: .meta) {
            meta = nestedMeta
        } else {
            let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            let generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
            let targetDate = try container.decodeIfPresent(String.self, forKey: .targetDate) ?? ""
            meta = DashboardMeta(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                forDate: targetDate,
                timezone: "Asia/Dubai"
            )
        }

        // All arrays default to empty if missing
        todayFacts = try container.decodeIfPresent(TodayFacts.self, forKey: .todayFacts)
        trends = try container.decodeIfPresent([TrendPeriod].self, forKey: .trends) ?? []
        feedStatus = try container.decodeIfPresent([FeedStatus].self, forKey: .feedStatus) ?? []
        staleFeeds = try container.decodeIfPresent([String].self, forKey: .staleFeeds) ?? []
        recentEvents = try container.decodeIfPresent([RecentEvent].self, forKey: .recentEvents) ?? []

        // Handle daily_insights: backend sends array directly, not wrapped in struct
        if let insightsStruct = try? container.decode(DailyInsights.self, forKey: .dailyInsights) {
            dailyInsights = insightsStruct
        } else if let insightsArray = try? container.decode([RankedInsight].self, forKey: .dailyInsights) {
            // Backend sends array directly - wrap in DailyInsights struct
            dailyInsights = DailyInsights(rankedInsights: insightsArray)
        } else {
            dailyInsights = nil
        }

        dataFreshness = try container.decodeIfPresent(DataFreshness.self, forKey: .dataFreshness)
        domainsStatus = try container.decodeIfPresent([DomainStatus].self, forKey: .domainsStatus)
        githubActivity = try container.decodeIfPresent(GitHubActivityWidget.self, forKey: .githubActivity)
        calendarSummary = try container.decodeIfPresent(CalendarSummary.self, forKey: .calendarSummary)
        reminderSummary = try container.decodeIfPresent(ReminderSummary.self, forKey: .reminderSummary)
        fasting = try container.decodeIfPresent(FastingStatus.self, forKey: .fasting)
        medicationsToday = try container.decodeIfPresent(MedicationsSummary.self, forKey: .medicationsToday)
        streaks = try container.decodeIfPresent(Streaks.self, forKey: .streaks)
        musicToday = try container.decodeIfPresent(MusicSummary.self, forKey: .musicToday)
        moodToday = try container.decodeIfPresent(MoodSummary.self, forKey: .moodToday)
        explainToday = try container.decodeIfPresent(ExplainToday.self, forKey: .explainToday)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meta, forKey: .meta)
        try container.encodeIfPresent(todayFacts, forKey: .todayFacts)
        try container.encode(trends, forKey: .trends)
        try container.encode(feedStatus, forKey: .feedStatus)
        try container.encode(staleFeeds, forKey: .staleFeeds)
        try container.encode(recentEvents, forKey: .recentEvents)
        try container.encodeIfPresent(dailyInsights, forKey: .dailyInsights)
        try container.encodeIfPresent(dataFreshness, forKey: .dataFreshness)
        try container.encodeIfPresent(domainsStatus, forKey: .domainsStatus)
        try container.encodeIfPresent(githubActivity, forKey: .githubActivity)
        try container.encodeIfPresent(calendarSummary, forKey: .calendarSummary)
        try container.encodeIfPresent(reminderSummary, forKey: .reminderSummary)
        try container.encodeIfPresent(fasting, forKey: .fasting)
        try container.encodeIfPresent(medicationsToday, forKey: .medicationsToday)
        try container.encodeIfPresent(streaks, forKey: .streaks)
        try container.encodeIfPresent(musicToday, forKey: .musicToday)
        try container.encodeIfPresent(moodToday, forKey: .moodToday)
        try container.encodeIfPresent(explainToday, forKey: .explainToday)
    }
}

// MARK: - Domain Status

struct DomainStatus: Codable, Identifiable {
    var id: String { domain }

    let domain: String
    let status: String
    let asOf: String?
    let lastSuccess: String?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case domain, status
        case asOf = "as_of"
        case lastSuccess = "last_success"
        case lastError = "last_error"
    }
}

// MARK: - Data Freshness

struct DataFreshness: Codable {
    let health: DomainFreshness?
    let finance: DomainFreshness?
    let overallStatus: String?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case health, finance
        case overallStatus = "overall_status"
        case generatedAt = "generated_at"
    }
}

struct DomainFreshness: Codable {
    let status: String
    let lastSync: String?
    let hoursSinceSync: Double?
    let staleFeeds: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case lastSync = "last_sync"
        case hoursSinceSync = "hours_since_sync"
        case staleFeeds = "stale_feeds"
    }

    var isStale: Bool { status != "healthy" }

    var lastSyncDate: Date? {
        guard let lastSync else { return nil }
        return Self.parseTimestamp(lastSync)
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }

        // Fallback: raw Postgres timestamp without timezone (e.g. "2026-01-30T13:00:15.192056")
        // Treat as UTC
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df.date(from: string) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df.date(from: string) { return d }
        // Postgres with space separator
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        if let d = df.date(from: string) { return d }
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: string)
    }

    var freshnessLabel: String {
        guard let date = lastSyncDate else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var syncTimeLabel: String {
        guard let date = lastSyncDate else { return "No sync" }
        let formatter = DateFormatter()
        if Constants.Dubai.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MMM d, HH:mm"
        }
        return "Synced \(formatter.string(from: date))"
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

    init(schemaVersion: Int, generatedAt: String, forDate: String, timezone: String) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.forDate = forDate
        self.timezone = timezone
    }

    /// Returns true if this dashboard data is for today in Dubai timezone
    var isForToday: Bool {
        let todayString = Constants.Dubai.dateString(from: Date())
        return forDate == todayString
    }

    /// Returns true if the data is stale (generated more than 5 minutes ago)
    var isDataOld: Bool {
        guard let generatedDate = DomainFreshness.parseTimestamp(generatedAt) else {
            return true
        }
        return Date().timeIntervalSince(generatedDate) > 300
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
    let proteinG: Double?
    let dataCompleteness: Double?
    let factsComputedAt: String?

    // Workout data
    let workoutCount: Int?
    let workoutMinutes: Int?

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
        case proteinG = "protein_g"
        case dataCompleteness = "data_completeness"
        case factsComputedAt = "facts_computed_at"
        case workoutCount = "workout_count"
        case workoutMinutes = "workout_minutes"
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
    let avgSteps: Double?
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
        case lastSync  // Backend sends camelCase "lastSync"
        case totalRecords = "total_records"
        case hoursSinceSync  // Backend sends camelCase "hoursSinceSync"
    }
}

enum FeedHealthStatus: String, Codable {
    case healthy
    case ok  // Backend sends "ok" for healthy status
    case stale
    case critical
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FeedHealthStatus(rawValue: rawValue) ?? .unknown
    }

    // Normalize "ok" to be treated same as "healthy"
    var isHealthy: Bool {
        self == .healthy || self == .ok
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

// MARK: - Daily Insights

struct DailyInsights: Codable {
    let alerts: [InsightAlert]?
    let patterns: [DayPattern]?
    let spendingByRecovery: [RecoverySpendLevel]?
    let todayIs: String?
    let rankedInsights: [RankedInsight]?

    enum CodingKeys: String, CodingKey {
        case alerts, patterns
        case spendingByRecovery = "spending_by_recovery"
        case todayIs = "today_is"
        case rankedInsights = "ranked_insights"
    }

    // Convenience init for when backend sends insights array directly
    init(rankedInsights: [RankedInsight]) {
        self.alerts = nil
        self.patterns = nil
        self.spendingByRecovery = nil
        self.todayIs = nil
        self.rankedInsights = rankedInsights
    }
}

struct InsightAlert: Codable, Identifiable {
    var id: String { "\(alertType)-\(description)" }
    let alertType: String
    let severity: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case severity, description
    }
}

struct DayPattern: Codable {
    let dayName: String
    let patternFlag: String
    let avgSpend: Double?
    let avgRecovery: Double?
    let sampleSize: Int?
    let daysWithSpend: Int?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case dayName = "day_name"
        case patternFlag = "pattern_flag"
        case avgSpend = "avg_spend"
        case avgRecovery = "avg_recovery"
        case sampleSize = "sample_size"
        case daysWithSpend = "days_with_spend"
        case confidence
    }
}

struct RecoverySpendLevel: Codable {
    let recoveryLevel: String
    let days: Int
    let daysWithSpend: Int?
    let avgSpend: Double?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case recoveryLevel = "recovery_level"
        case days
        case daysWithSpend = "days_with_spend"
        case avgSpend = "avg_spend"
        case confidence
    }
}

struct RankedInsight: Codable, Identifiable {
    var id: String { "\(type)-\(description)" }
    let type: String
    let confidence: String
    let description: String
    let daysSampled: Int
    let daysWithData: Int
    let icon: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case type, confidence, description, icon, color
        case daysSampled = "days_sampled"
        case daysWithData = "days_with_data"
    }
}

// MARK: - GitHub Activity Widget

struct GitHubActivityWidget: Codable {
    let summary: GitHubSummary
    let daily: [GitHubDailyActivity]
    let repos: [GitHubRepo]
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case summary, daily, repos
        case generatedAt = "generated_at"
    }
}

struct GitHubSummary: Codable {
    let activeDays7d: Int
    let pushEvents7d: Int
    let activeDays30d: Int
    let pushEvents30d: Int
    let repos7d: Int
    let currentStreak: Int
    let maxStreak90d: Int
    let asOfDate: String?

    enum CodingKeys: String, CodingKey {
        case activeDays7d = "active_days_7d"
        case pushEvents7d = "push_events_7d"
        case activeDays30d = "active_days_30d"
        case pushEvents30d = "push_events_30d"
        case repos7d = "repos_7d"
        case currentStreak = "current_streak"
        case maxStreak90d = "max_streak_90d"
        case asOfDate = "as_of_date"
    }
}

struct GitHubDailyActivity: Codable, Identifiable {
    var id: String { day }

    let day: String
    let pushEvents: Int
    let reposTouched: Int
    let productivityScore: Int

    enum CodingKeys: String, CodingKey {
        case day
        case pushEvents = "push_events"
        case reposTouched = "repos_touched"
        case productivityScore = "productivity_score"
    }
}

struct GitHubRepo: Codable, Identifiable {
    var id: String { name }

    let name: String
    let events30d: Int
    let lastActive: String

    enum CodingKeys: String, CodingKey {
        case name
        case events30d = "events_30d"
        case lastActive = "last_active"
    }
}

// MARK: - Calendar Summary

struct CalendarSummary: Codable {
    let meetingCount: Int
    let meetingHours: Double
    let firstMeeting: String?
    let lastMeeting: String?

    enum CodingKeys: String, CodingKey {
        case meetingCount = "meeting_count"
        case meetingHours = "meeting_hours"
        case firstMeeting = "first_meeting"
        case lastMeeting = "last_meeting"
    }
}

// MARK: - Reminder Summary

struct ReminderSummary: Codable {
    let dueToday: Int
    let completedToday: Int
    let overdueCount: Int

    enum CodingKeys: String, CodingKey {
        case dueToday = "due_today"
        case completedToday = "completed_today"
        case overdueCount = "overdue_count"
    }
}

// MARK: - Medications Summary

struct MedicationsSummary: Codable {
    let dueToday: Int
    let takenToday: Int
    let skippedToday: Int
    let adherencePct: Double?
    let medications: [MedicationDose]?

    enum CodingKeys: String, CodingKey {
        case dueToday = "due_today"
        case takenToday = "taken_today"
        case skippedToday = "skipped_today"
        case adherencePct = "adherence_pct"
        case medications
    }
}

struct MedicationDose: Codable, Identifiable {
    var id: String { "\(name)-\(scheduledTime ?? "none")" }

    let name: String
    let status: String
    let scheduledTime: String?
    let takenAt: String?

    enum CodingKeys: String, CodingKey {
        case name, status
        case scheduledTime = "scheduled_time"
        case takenAt = "taken_at"
    }
}

// MARK: - Fasting Status

struct FastingStatus: Codable {
    let isActive: Bool
    let sessionId: Int?
    let startedAt: String?
    let elapsedHours: Double?
    let hoursSinceMeal: Double?
    let lastMealAt: String?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case sessionId = "session_id"
        case startedAt = "started_at"
        case elapsedHours = "elapsed_hours"
        case hoursSinceMeal = "hours_since_meal"
        case lastMealAt = "last_meal_at"
    }

    /// Format elapsed hours as HH:MM (for explicit fasting session)
    var elapsedFormatted: String {
        guard let hours = elapsedHours else { return "--:--" }
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d", h, m)
    }

    /// Format hours since last meal as HH:MM (for passive IF tracking)
    var sinceMealFormatted: String {
        guard let hours = hoursSinceMeal else { return "--:--" }
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d", h, m)
    }

    /// Display timer: use explicit session if active, otherwise passive since-meal
    var displayTimer: String {
        if isActive, elapsedHours != nil {
            return elapsedFormatted
        }
        return sinceMealFormatted
    }

    /// Progress toward common IF goals (16h, 18h, 20h)
    var fastingGoalProgress: (hours: Double, goal: Int, progress: Double)? {
        let hours = isActive ? elapsedHours : hoursSinceMeal
        guard let h = hours, h > 0 else { return nil }

        // Common IF windows
        let goals = [16, 18, 20, 24]
        // Pick the goal user is closest to achieving
        let goal = goals.first(where: { Double($0) >= h }) ?? 24
        let progress = min(h / Double(goal), 1.0)
        return (h, goal, progress)
    }

    var startedAtDate: Date? {
        guard let startedAt else { return nil }
        return DomainFreshness.parseTimestamp(startedAt)
    }

    var lastMealDate: Date? {
        guard let lastMealAt else { return nil }
        return DomainFreshness.parseTimestamp(lastMealAt)
    }
}

// MARK: - Streaks

struct Streaks: Codable {
    let water: StreakData
    let meals: StreakData
    let weight: StreakData
    let workout: StreakData
    let overall: StreakData
    let computedAt: String?

    enum CodingKeys: String, CodingKey {
        case water, meals, weight, workout, overall
        case computedAt = "computed_at"
    }

    /// Returns the best active streak (non-zero current)
    var bestActiveStreak: (name: String, current: Int, best: Int)? {
        let all = [
            ("Weight", weight),
            ("Water", water),
            ("Meals", meals),
            ("Workout", workout)
        ]
        let active = all.filter { $0.1.current > 0 }.sorted { $0.1.current > $1.1.current }
        guard let top = active.first else { return nil }
        return (top.0, top.1.current, top.1.best)
    }

    /// Returns all streaks sorted by current value descending
    var sortedStreaks: [(name: String, icon: String, data: StreakData)] {
        [
            ("Weight", "scalemass", weight),
            ("Water", "drop.fill", water),
            ("Meals", "fork.knife", meals),
            ("Workout", "figure.run", workout)
        ].sorted { $0.2.current > $1.2.current }
    }
}

struct StreakData: Codable {
    let current: Int
    let best: Int

    /// True if currently on a streak
    var isActive: Bool { current > 0 }

    /// True if currently at personal best
    var isAtBest: Bool { current > 0 && current >= best }
}

// MARK: - Music Summary

struct MusicSummary: Codable {
    let tracksPlayed: Int
    let totalMinutes: Double
    let uniqueArtists: Int
    let topArtist: String?
    let topAlbum: String?

    enum CodingKeys: String, CodingKey {
        case tracksPlayed = "tracks_played"
        case totalMinutes = "total_minutes"
        case uniqueArtists = "unique_artists"
        case topArtist = "top_artist"
        case topAlbum = "top_album"
    }

    var hasActivity: Bool { tracksPlayed > 0 }
}

// MARK: - Mood Summary

struct MoodSummary: Codable {
    let moodScore: Int?
    let energyScore: Int?
    let loggedAt: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case moodScore = "mood_score"
        case energyScore = "energy_score"
        case loggedAt = "logged_at"
        case notes
    }

    var hasData: Bool { moodScore != nil }

    var moodEmoji: String {
        guard let score = moodScore else { return "" }
        let emojis = ["😫", "😢", "😔", "😐", "🙂", "😊", "😄", "😁", "🤩", "🥳"]
        let index = max(0, min(score - 1, emojis.count - 1))
        return emojis[index]
    }

    var energyEmoji: String {
        guard let score = energyScore else { return "" }
        let emojis = ["🪫", "😴", "🥱", "😑", "😐", "🙂", "😀", "💪", "⚡️", "🔥"]
        let index = max(0, min(score - 1, emojis.count - 1))
        return emojis[index]
    }
}

// MARK: - Explain Today

struct ExplainToday: Codable {
    let targetDate: String
    let hasData: Bool
    let briefing: String
    let dataGaps: [String]
    let dataCompleteness: Double?
    let computedAt: String?
    let assertions: ExplainTodayAssertions?
    let health: ExplainTodayHealth?
    let finance: ExplainTodayFinance?
    let activity: ExplainTodayActivity?
    let nutrition: ExplainTodayNutrition?

    enum CodingKeys: String, CodingKey {
        case targetDate = "target_date"
        case hasData = "has_data"
        case briefing
        case dataGaps = "data_gaps"
        case dataCompleteness = "data_completeness"
        case computedAt = "computed_at"
        case assertions
        case health, finance, activity, nutrition
    }
}

struct ExplainTodayHealth: Codable {
    let summary: [String]
    let recoveryScore: Int?
    let recoveryLabel: String?
    let hrv: Double?
    let strain: Double?
    let sleepHours: Double?
    let sleepLabel: String?
    let weightKg: Double?

    enum CodingKeys: String, CodingKey {
        case summary
        case recoveryScore = "recovery_score"
        case recoveryLabel = "recovery_label"
        case hrv, strain
        case sleepHours = "sleep_hours"
        case sleepLabel = "sleep_label"
        case weightKg = "weight_kg"
    }
}

struct ExplainTodayFinance: Codable {
    let summary: [String]
    let spendTotal: Double?
    let spendLabel: String?
    let transactionCount: Int?

    enum CodingKeys: String, CodingKey {
        case summary
        case spendTotal = "spend_total"
        case spendLabel = "spend_label"
        case transactionCount = "transaction_count"
    }
}

struct ExplainTodayActivity: Codable {
    let summary: [String]
    let fastingHours: Double?
    let remindersDue: Int?
    let remindersCompleted: Int?
    let listeningMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case summary
        case fastingHours = "fasting_hours"
        case remindersDue = "reminders_due"
        case remindersCompleted = "reminders_completed"
        case listeningMinutes = "listening_minutes"
    }
}

struct ExplainTodayNutrition: Codable {
    let summary: [String]
    let calories: Int?
    let proteinG: Double?
    let waterMl: Int?
    let mealsLogged: Int?

    enum CodingKeys: String, CodingKey {
        case summary, calories
        case proteinG = "protein_g"
        case waterMl = "water_ml"
        case mealsLogged = "meals_logged"
    }
}

struct ExplainTodayAssertions: Codable {
    let dubaiDayValid: Bool?
    let dataFresh: Bool?
    let dataSufficient: Bool?
    let allPassed: Bool?
    let dataCompleteness: Double?

    enum CodingKeys: String, CodingKey {
        case dubaiDayValid = "dubai_day_valid"
        case dataFresh = "data_fresh"
        case dataSufficient = "data_sufficient"
        case allPassed = "all_passed"
        case dataCompleteness = "data_completeness"
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

// MARK: - Medication Creation Models

struct MedicationCreateRequest: Codable {
    let medication_name: String
    let brand: String?
    let dose_quantity: Double?
    let dose_unit: String?
    let frequency: String
    let times_of_day: [String]
    let notes: String?
}

struct MedicationCreateResponse: Codable {
    let success: Bool
    let medication_id: Int
}
