import Foundation
import SwiftUI
import WidgetKit
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var summary = DailySummary()
    @Published var recentLogs: [LogEntry] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var lastSyncDate: Date?

    // New unified dashboard payload
    @Published var dashboardPayload: DashboardPayload?
    @Published var dataSource: DashboardResult.DataSource?
    @Published var isDataStale = false
    @Published var lastUpdatedFormatted: String?

    private let dashboardService = DashboardService.shared

    // MARK: - Computed Properties for Legacy View Compatibility

    /// Recovery metrics from unified payload (for WHOOPRecoveryRow)
    var recoveryMetrics: RecoveryMetrics? {
        guard let facts = dashboardPayload?.todayFacts,
              facts.recoveryScore != nil || facts.hrv != nil || facts.rhr != nil else {
            return nil
        }
        return RecoveryMetrics(
            recoveryScore: facts.recoveryScore,
            hrv: facts.hrv,
            rhr: facts.rhr,
            spo2: nil,
            skinTemp: nil
        )
    }

    /// Sleep metrics from unified payload (for WHOOPSleepRow)
    var sleepMetrics: SleepMetrics? {
        guard let facts = dashboardPayload?.todayFacts,
              facts.sleepMinutes != nil else {
            return nil
        }
        return SleepMetrics(
            timeInBedMin: facts.sleepMinutes,
            awakeMin: nil,
            lightSleepMin: facts.lightSleepMinutes,
            deepSleepMin: facts.deepSleepMinutes,
            remSleepMin: facts.remSleepMinutes,
            sleepEfficiency: facts.sleepEfficiency,
            sleepConsistency: nil,
            sleepPerformance: facts.sleepEfficiency != nil ? Int(facts.sleepEfficiency!) : nil,
            sleepNeededMin: nil,
            sleepDebtMin: nil,
            cycles: nil,
            disturbances: nil,
            respiratoryRate: nil
        )
    }

    /// Stale feeds from payload
    var staleFeeds: [String] {
        dashboardPayload?.staleFeeds ?? []
    }

    /// Whether any feeds are stale
    var hasStaleFeeds: Bool {
        !staleFeeds.isEmpty
    }
    private let storage = SharedStorage.shared
    private var loadTask: Task<Void, Never>?

    init() {
        loadFromCache()
        loadTodaysSummary()
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Load Data

    private func loadFromCache() {
        // Try to load cached dashboard payload first
        if let cachedResult = dashboardService.loadCached() {
            dashboardPayload = cachedResult.payload
            dataSource = cachedResult.source
            isDataStale = cachedResult.isStale
            lastUpdatedFormatted = cachedResult.lastUpdatedFormatted
            lastSyncDate = cachedResult.lastUpdated

            // Map to DailySummary for backwards compatibility
            mapPayloadToSummary(cachedResult.payload)
        } else {
            // Fall back to SharedStorage for widgets
            let cached = SharedStorage.DailySummary.current()
            summary.totalCalories = cached.calories
            summary.totalProtein = cached.protein
            summary.totalWater = cached.water
            summary.latestWeight = cached.weight
            lastSyncDate = cached.lastUpdate
        }

        // Load recent logs
        let logsData = storage.getRecentLogs()
        recentLogs = logsData.compactMap { dict -> LogEntry? in
            guard let type = dict["type"] as? String,
                  let description = dict["description"] as? String,
                  let timestamp = dict["timestamp"] as? TimeInterval else {
                return nil
            }

            let logType = LogType(rawValue: type) ?? .other
            return LogEntry(
                timestamp: Date(timeIntervalSince1970: timestamp),
                type: logType,
                description: description,
                calories: dict["calories"] as? Int,
                protein: dict["protein"] as? Double
            )
        }
    }

    private func mapPayloadToSummary(_ payload: DashboardPayload) {
        summary.totalCalories = payload.todayFacts.caloriesConsumed ?? 0
        summary.totalWater = payload.todayFacts.waterMl ?? 0
        summary.latestWeight = payload.todayFacts.weightKg
        summary.weight = payload.todayFacts.weightKg
    }

    func loadTodaysSummary() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadTask = Task {
            guard !Task.isCancelled else { return }
            do {
                // Fetch from unified dashboard endpoint
                let result = try await dashboardService.fetchDashboard()

                await MainActor.run {
                    // Update dashboard payload
                    dashboardPayload = result.payload
                    dataSource = result.source
                    isDataStale = result.isStale
                    lastUpdatedFormatted = result.lastUpdatedFormatted
                    lastSyncDate = result.lastUpdated

                    // Map to DailySummary for backwards compatibility
                    mapPayloadToSummary(result.payload)

                    // Map recent events to recent logs
                    recentLogs = result.payload.recentEvents.prefix(10).compactMap { event -> LogEntry? in
                        let timestamp = ISO8601DateFormatter().date(from: "\(event.eventDate)T\(event.eventTime)") ?? Date()
                        let type = mapEventTypeToLogType(event.eventType)
                        let description = formatEventDescription(event)

                        return LogEntry(
                            timestamp: timestamp,
                            type: type,
                            description: description,
                            calories: nil,
                            protein: nil
                        )
                    }

                    // Save to SharedStorage for widgets
                    saveToStorage()

                    // Clear error if we got data from cache
                    if result.source == .cache {
                        errorMessage = "Using cached data"
                    } else {
                        errorMessage = nil
                    }

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Show error but keep cached data
                    if dashboardPayload == nil && recentLogs.isEmpty {
                        errorMessage = "Failed to load data. Please try again."
                    } else {
                        errorMessage = "Using cached data - sync failed"
                    }
                    lastSyncDate = Date()
                }
            }
        }
    }

    private func mapEventTypeToLogType(_ eventType: String) -> LogType {
        switch eventType {
        case "weight":
            return .weight
        case "food":
            return .food
        case "water":
            return .water
        case "mood":
            return .mood
        default:
            return .other
        }
    }

    private func formatEventDescription(_ event: RecentEvent) -> String {
        switch event.eventType {
        case "transaction":
            if let merchant = event.payload.merchant, let amount = event.payload.amount {
                return "\(merchant): \(String(format: "%.2f", amount)) AED"
            }
            return "Transaction"
        case "weight":
            if let weight = event.payload.weightKg {
                return "Weight: \(String(format: "%.1f", weight)) kg"
            }
            return "Weight logged"
        default:
            return event.payload.description ?? event.eventType
        }
    }

    func refresh() async {
        isRefreshing = true
        errorMessage = nil

        do {
            let result = try await dashboardService.fetchDashboard()

            dashboardPayload = result.payload
            dataSource = result.source
            isDataStale = result.isStale
            lastUpdatedFormatted = result.lastUpdatedFormatted
            lastSyncDate = result.lastUpdated

            mapPayloadToSummary(result.payload)
            saveToStorage()

            if result.source == .cache {
                errorMessage = "Using cached data"
            }
        } catch {
            // Keep existing data, show error
            errorMessage = "Refresh failed - using cached data"
        }

        isRefreshing = false
    }

    // MARK: - Update After Logging

    func updateSummaryAfterLog(type: LogType, response: NexusResponse) {
        // Update local summary
        if let data = response.data {
            if let calories = data.calories {
                summary.totalCalories += calories
            }
            if let protein = data.protein {
                summary.totalProtein += protein
            }
            if let water = data.total_water_ml {
                summary.totalWater = water
            }
            if let weight = data.weight_kg {
                summary.latestWeight = weight
                summary.weight = weight
            }
        }

        // Save to SharedStorage for widgets
        saveToStorage()

        // Add to recent logs
        addRecentLog(
            type: type,
            description: response.message ?? "Logged",
            calories: response.data?.calories,
            protein: response.data?.protein
        )

        // Update timestamp
        lastSyncDate = Date()

        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func addRecentLog(type: LogType, description: String, calories: Int?, protein: Double?) {
        let entry = LogEntry(
            timestamp: Date(),
            type: type,
            description: description,
            calories: calories,
            protein: protein
        )

        recentLogs.insert(entry, at: 0)

        // Keep only last 10
        if recentLogs.count > 10 {
            recentLogs = Array(recentLogs.prefix(10))
        }

        // Save to SharedStorage
        storage.saveRecentLog(
            type: type.rawValue,
            description: description,
            calories: calories,
            protein: protein
        )
    }

    // MARK: - Persistence

    private func saveToStorage() {
        storage.saveDailySummary(
            calories: summary.totalCalories,
            protein: summary.totalProtein,
            water: summary.totalWater,
            weight: summary.latestWeight
        )
    }

    func resetDailyStats() {
        summary = DailySummary()
        recentLogs = []
        storage.resetDailyStats()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
