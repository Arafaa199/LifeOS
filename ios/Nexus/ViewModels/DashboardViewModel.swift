import Foundation
import SwiftUI
import WidgetKit
import Combine
import os

// MARK: - Refresh Reason

enum RefreshReason: String {
    case foreground
    case pullToRefresh
    case force
}

// MARK: - Refresh Log Entry

struct RefreshLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let reason: RefreshReason
    let outcome: Outcome
    let durationMs: Int

    enum Outcome: String {
        case success
        case timeout
        case error
        case cancelled
        case debounced
    }

    var summary: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return "\(fmt.string(from: timestamp)) [\(reason.rawValue)] \(outcome.rawValue) (\(durationMs)ms)"
    }
}

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

    // Foreground refresh state
    @Published var isForegroundRefreshing = false
    @Published var foregroundRefreshFailed = false
    @Published var lastRefreshReason: RefreshReason?
    @Published private(set) var refreshLog: [RefreshLogEntry] = []

    private let refreshLogger = Logger(subsystem: "com.nexus.lifeos", category: "refresh")
    private let maxRefreshLogEntries = 20

    // Meal confirmations
    @Published var pendingMeals: [InferredMeal] = []

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

    var healthFreshness: DomainFreshness? {
        dashboardPayload?.dataFreshness?.health
    }

    var financeFreshness: DomainFreshness? {
        dashboardPayload?.dataFreshness?.finance
    }

    var hasAnyStaleData: Bool {
        if let overall = dashboardPayload?.dataFreshness?.overallStatus, overall != "healthy" {
            return true
        }
        return isDataStale || foregroundRefreshFailed
    }
    private let storage = SharedStorage.shared
    private var loadTask: Task<Void, Never>?
    private var foregroundRefreshTask: Task<Void, Never>?
    private var lastForegroundRefreshDate: Date?
    private let foregroundRefreshMinInterval: TimeInterval = 30

    init() {
        loadFromCache()
        loadTodaysSummary()
    }

    deinit {
        loadTask?.cancel()
        foregroundRefreshTask?.cancel()
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
        // Cancel any in-flight foreground refresh — pull-to-refresh takes priority
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        isForegroundRefreshing = false

        lastRefreshReason = .pullToRefresh
        isRefreshing = true
        errorMessage = nil
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let result = try await dashboardService.fetchDashboard()

            dashboardPayload = result.payload
            dataSource = result.source
            isDataStale = result.isStale
            lastUpdatedFormatted = result.lastUpdatedFormatted
            lastSyncDate = result.lastUpdated
            foregroundRefreshFailed = false
            lastForegroundRefreshDate = Date()

            mapPayloadToSummary(result.payload)
            saveToStorage()

            if result.source == .cache {
                errorMessage = "Using cached data"
            }

            // Load pending meal confirmations
            await loadPendingMeals()
            recordRefresh(reason: .pullToRefresh, outcome: .success, start: start)
        } catch {
            // Keep existing data, show error
            errorMessage = "Refresh failed - using cached data"
            recordRefresh(reason: .pullToRefresh, outcome: .error, start: start)
        }

        isRefreshing = false
    }

    func foregroundRefresh(reason: RefreshReason = .foreground) {
        guard dashboardPayload != nil else { return }

        // Debounce: skip if last refresh was recent (force bypasses)
        if reason != .force,
           let last = lastForegroundRefreshDate,
           Date().timeIntervalSince(last) < foregroundRefreshMinInterval {
            recordRefresh(reason: reason, outcome: .debounced, durationMs: 0)
            return
        }

        // Cancel any in-flight foreground refresh
        foregroundRefreshTask?.cancel()

        foregroundRefreshTask = Task {
            lastRefreshReason = reason
            isForegroundRefreshing = true
            foregroundRefreshFailed = false
            let start = CFAbsoluteTimeGetCurrent()

            do {
                let result = try await withThrowingTaskGroup(of: DashboardResult.self) { group in
                    group.addTask {
                        try await self.dashboardService.fetchDashboard()
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        throw DashboardError.timeout
                    }

                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }

                guard !Task.isCancelled else {
                    recordRefresh(reason: reason, outcome: .cancelled, start: start)
                    return
                }

                dashboardPayload = result.payload
                dataSource = result.source
                isDataStale = result.isStale
                lastUpdatedFormatted = result.lastUpdatedFormatted
                lastSyncDate = result.lastUpdated
                foregroundRefreshFailed = false
                lastForegroundRefreshDate = Date()

                mapPayloadToSummary(result.payload)
                saveToStorage()
                errorMessage = nil
                recordRefresh(reason: reason, outcome: .success, start: start)
            } catch is CancellationError {
                recordRefresh(reason: reason, outcome: .cancelled, start: start)
            } catch {
                guard !Task.isCancelled else {
                    recordRefresh(reason: reason, outcome: .cancelled, start: start)
                    return
                }
                foregroundRefreshFailed = true
                let outcome: RefreshLogEntry.Outcome
                if case DashboardError.timeout = error {
                    outcome = .timeout
                } else {
                    outcome = .error
                }
                recordRefresh(reason: reason, outcome: outcome, start: start)
            }

            if !Task.isCancelled {
                isForegroundRefreshing = false
            }
        }
    }

    func forceRefresh() {
        foregroundRefresh(reason: .force)
    }

    // MARK: - Refresh Logging

    private func recordRefresh(reason: RefreshReason, outcome: RefreshLogEntry.Outcome, start: CFAbsoluteTime) {
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        recordRefresh(reason: reason, outcome: outcome, durationMs: ms)
    }

    private func recordRefresh(reason: RefreshReason, outcome: RefreshLogEntry.Outcome, durationMs: Int) {
        let entry = RefreshLogEntry(timestamp: Date(), reason: reason, outcome: outcome, durationMs: durationMs)
        refreshLog.append(entry)
        if refreshLog.count > maxRefreshLogEntries {
            refreshLog.removeFirst(refreshLog.count - maxRefreshLogEntries)
        }
        refreshLogger.info("\(entry.summary)")
    }

    func loadPendingMeals() async {
        do {
            pendingMeals = try await NexusAPI.shared.fetchPendingMealConfirmations()
        } catch {
            // Silently fail - meal confirmations are optional
            pendingMeals = []
        }
    }

    func confirmMeal(_ meal: InferredMeal, action: String) async {
        do {
            _ = try await NexusAPI.shared.confirmMeal(
                mealDate: meal.mealDate,
                mealTime: meal.mealTime,
                mealType: meal.mealType,
                action: action
            )

            // Remove from pending list
            pendingMeals.removeAll { $0.id == meal.id }
        } catch {
            // Show error
            errorMessage = "Failed to save meal confirmation"
        }
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
