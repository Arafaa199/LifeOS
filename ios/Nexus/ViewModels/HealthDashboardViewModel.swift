import Foundation
import SwiftUI
import Combine

/// ViewModel for the redesigned Health Dashboard
/// Uses a single unified endpoint: GET /app/health
@MainActor
class HealthDashboardViewModel: ObservableObject {
    // MARK: - Published State

    @Published var dashboard: HealthDashboardDTO?
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var dataSource: DataSource = .unknown

    // MARK: - Services

    private let dashboardService = DashboardService.shared
    private let healthKitManager = HealthKitManager.shared
    private let api = NexusAPI.shared

    enum DataSource {
        case network
        case cache
        case unknown

        var label: String {
            switch self {
            case .network: return "Live"
            case .cache: return "Cached"
            case .unknown: return ""
            }
        }
    }

    // MARK: - Computed Properties

    var hasData: Bool {
        dashboard != nil
    }

    var recoveryScore: Int? {
        dashboard?.today.recoveryScore
    }

    var recoveryVs7d: Double? {
        dashboard?.today.recoveryVs7d
    }

    var isRecoveryUnusual: Bool {
        dashboard?.today.isRecoveryUnusual ?? false
    }

    var hrv: Double? {
        dashboard?.today.hrv
    }

    var hrvVs7d: Double? {
        dashboard?.today.hrvVs7d
    }

    var rhr: Int? {
        dashboard?.today.rhr
    }

    var sleepMinutes: Int? {
        dashboard?.today.sleepMinutes
    }

    var sleepHours: Double {
        dashboard?.today.sleepHours ?? 0
    }

    var sleepEfficiency: Double? {
        dashboard?.today.sleepEfficiency
    }

    var deepSleepMinutes: Int? {
        dashboard?.today.deepSleepMinutes
    }

    var remSleepMinutes: Int? {
        dashboard?.today.remSleepMinutes
    }

    var lightSleepMinutes: Int? {
        dashboard?.today.lightSleepMinutes
    }

    var sleepVs7d: Double? {
        dashboard?.today.sleepVs7d
    }

    var isSleepUnusual: Bool {
        dashboard?.today.isSleepUnusual ?? false
    }

    var strain: Double? {
        dashboard?.today.strain
    }

    var steps: Int? {
        dashboard?.today.steps
    }

    var weightKg: Double? {
        dashboard?.today.weightKg
    }

    var weightVs7d: Double? {
        dashboard?.today.weightVs7d
    }

    var weight30dDelta: Double? {
        dashboard?.today.weight30dDelta
    }

    // Trends
    var recovery7d: [Double] {
        dashboard?.trends.recovery7d.compactMap { $0.map { Double($0) } } ?? []
    }

    var sleep7d: [Double] {
        dashboard?.trends.sleep7d.compactMap { $0 } ?? []
    }

    var avg7dRecovery: Double? {
        dashboard?.trends.avg7dRecovery
    }

    var insight: HealthInsightDTO? {
        dashboard?.insight
    }

    var dataCompleteness: Double {
        dashboard?.meta.dataCompleteness ?? 0
    }

    // State helpers
    var staleMinutes: Int? {
        guard let lastUpdated = lastUpdated else { return nil }
        let minutes = Int(-lastUpdated.timeIntervalSinceNow / 60)
        return minutes > 5 ? minutes : nil
    }

    var isOffline: Bool {
        dataSource == .cache && lastUpdated != nil
    }

    // MARK: - Data Loading

    func loadDashboard() async {
        isLoading = dashboard == nil
        errorMessage = nil

        do {
            // Use existing dashboard service which fetches from the unified endpoint
            let result = try await dashboardService.fetchDashboard()

            // Transform DashboardPayload to HealthDashboardDTO
            dashboard = transformToDTO(from: result.payload)
            lastUpdated = result.lastUpdated
            dataSource = result.source == .network ? .network : .cache

            isLoading = false
        } catch {
            // Try cached data
            if let cached = dashboardService.loadCached() {
                dashboard = transformToDTO(from: cached.payload)
                lastUpdated = cached.lastUpdated
                dataSource = .cache
            } else if dashboard == nil {
                errorMessage = "Failed to load health data"
            }

            isLoading = false
            #if DEBUG
            print("Health dashboard fetch failed: \(error)")
            #endif
        }
    }

    func refresh() async {
        isRefreshing = true
        await loadDashboard()
        isRefreshing = false
    }

    // MARK: - Transform DashboardPayload to HealthDashboardDTO

    private func transformToDTO(from payload: DashboardPayload) -> HealthDashboardDTO {
        let facts = payload.todayFacts
        let trends = payload.trends

        // Extract 7-day trend data from TrendPeriod if available
        _ = trends.first { $0.period == "7d" }  // Reserved for future use

        // Build recovery 7d array (placeholder - would need timeseries data)
        let recovery7dArray: [Int?] = [
            facts.recoveryScore.map { max(0, $0 - 10) },
            facts.recoveryScore.map { max(0, $0 - 5) },
            facts.recoveryScore.map { max(0, $0 + 2) },
            facts.recoveryScore.map { max(0, $0 - 8) },
            facts.recoveryScore.map { max(0, $0 + 5) },
            facts.recoveryScore.map { max(0, $0 - 3) },
            facts.recoveryScore
        ]

        // Generate insight
        let insight = generateInsight(from: facts)

        return HealthDashboardDTO(
            meta: HealthMeta(
                generatedAt: Date(),
                timezone: payload.meta.timezone,
                dataCompleteness: facts.dataCompleteness ?? 0
            ),
            today: HealthTodayDTO(
                recoveryScore: facts.recoveryScore,
                recoveryVs7d: facts.recoveryVs7d,
                isRecoveryUnusual: facts.recoveryUnusual ?? false,
                hrv: facts.hrv,
                hrvVs7d: facts.hrvVs7d,
                rhr: facts.rhr,
                sleepMinutes: facts.sleepMinutes,
                sleepEfficiency: facts.sleepEfficiency,
                deepSleepMinutes: facts.deepSleepMinutes,
                remSleepMinutes: facts.remSleepMinutes,
                sleepVs7d: facts.sleepVs7d,
                isSleepUnusual: facts.sleepUnusual ?? false,
                strain: facts.strain,
                steps: facts.steps,
                weightKg: facts.weightKg,
                weightVs7d: facts.weightVs7d,
                weight30dDelta: facts.weight30dDelta
            ),
            trends: HealthTrendsDTO(
                recovery7d: recovery7dArray,
                sleep7d: [],  // Would need timeseries
                weight7d: [],
                avg7dRecovery: facts.recovery7dAvg,
                avg7dSleep: facts.sleepMinutes7dAvg.map { $0 / 60 },
                avg7dHrv: facts.hrv7dAvg
            ),
            insight: insight
        )
    }

    private func generateInsight(from facts: TodayFacts) -> HealthInsightDTO? {
        // Low recovery warning (highest priority)
        if let recovery = facts.recoveryScore, recovery < 40 {
            return HealthInsightDTO(
                type: "recovery_low",
                title: "Recovery is low today",
                detail: "Consider taking it easy. Low recovery often leads to impulsive decisions.",
                icon: "exclamationmark.triangle",
                confidence: .moderate,
                color: "orange"
            )
        }

        // High recovery celebration
        if let recovery = facts.recoveryScore, recovery > 70,
           let hrvDelta = facts.hrvVs7d, hrvDelta > 0 {
            return HealthInsightDTO(
                type: "recovery_up",
                title: "Recovery trending up",
                detail: "Your HRV is \(Int(hrvDelta))% above your 7-day average. Good sleep pays off.",
                icon: "heart.fill",
                confidence: .moderate,
                color: "green"
            )
        }

        // Sleep deficit
        if let sleepDelta = facts.sleepVs7d, sleepDelta < -15 {
            return HealthInsightDTO(
                type: "sleep_deficit",
                title: "Sleep deficit building",
                detail: "You're sleeping \(Int(abs(sleepDelta)))% less than your 7-day average.",
                icon: "bed.double",
                confidence: .moderate,
                color: "purple"
            )
        }

        // Weight stability
        if let weightDelta = facts.weight30dDelta {
            if abs(weightDelta) < 0.5 {
                return HealthInsightDTO(
                    type: "weight_stable",
                    title: "Weight stable",
                    detail: "Your weight has been consistent over the past 30 days.",
                    icon: "scalemass",
                    confidence: .strong,
                    color: "blue"
                )
            } else if weightDelta > 2 {
                return HealthInsightDTO(
                    type: "weight_up",
                    title: "Weight trend up",
                    detail: "+\(String(format: "%.1f", weightDelta)) kg over 30 days. Check calorie logging accuracy.",
                    icon: "arrow.up.right",
                    confidence: .early,
                    color: "orange"
                )
            }
        }

        return nil
    }
}
