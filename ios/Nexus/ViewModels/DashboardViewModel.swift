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
    private let coordinator = SyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties for Legacy View Compatibility

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

    var staleFeeds: [String] {
        dashboardPayload?.staleFeeds ?? []
    }

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

    init() {
        loadFromCache()
        subscribeToCoordinator()
    }

    // MARK: - Coordinator Subscription

    private func subscribeToCoordinator() {
        coordinator.$dashboardPayload
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handlePayloadUpdate(payload)
            }
            .store(in: &cancellables)

        // Freshness contract: mirror coordinator syncing state immediately.
        // isSyncingAll is set synchronously in syncAll(), so this fires
        // within the same run-loop pass — well under 300ms.
        coordinator.$isSyncingAll
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncing in
                self?.isForegroundRefreshing = syncing
            }
            .store(in: &cancellables)
    }

    private func handlePayloadUpdate(_ payload: DashboardPayload) {
        dashboardPayload = payload
        dataSource = .network
        isDataStale = false
        lastUpdatedFormatted = RelativeDateTimeFormatter().localizedString(for: Date(), relativeTo: Date())
        lastSyncDate = Date()
        foregroundRefreshFailed = false

        mapPayloadToSummary(payload)

        recentLogs = payload.recentEvents.prefix(10).compactMap { event -> LogEntry? in
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

        saveToStorage()
        errorMessage = nil
        isLoading = false
        // isForegroundRefreshing is driven by coordinator.$isSyncingAll subscription
    }

    // MARK: - Load Data

    private func loadFromCache() {
        if let cachedResult = dashboardService.loadCached() {
            dashboardPayload = cachedResult.payload
            dataSource = cachedResult.source
            isDataStale = cachedResult.isStale
            lastUpdatedFormatted = cachedResult.lastUpdatedFormatted
            lastSyncDate = cachedResult.lastUpdated

            mapPayloadToSummary(cachedResult.payload)
        } else {
            let cached = SharedStorage.DailySummary.current()
            summary.totalCalories = cached.calories
            summary.totalProtein = cached.protein
            summary.totalWater = cached.water
            summary.latestWeight = cached.weight
            lastSyncDate = cached.lastUpdate
        }

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

    private func mapEventTypeToLogType(_ eventType: String) -> LogType {
        switch eventType {
        case "weight": return .weight
        case "food": return .food
        case "water": return .water
        case "mood": return .mood
        default: return .other
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

    // MARK: - Refresh (delegates to coordinator)

    func refresh() async {
        lastRefreshReason = .pullToRefresh
        isRefreshing = true
        errorMessage = nil
        let start = CFAbsoluteTimeGetCurrent()

        coordinator.syncAll(force: true)

        // Poll coordinator state until sync completes (max 10s).
        // No arbitrary sleep — pull-to-refresh spinner stays visible
        // until real work finishes.
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !coordinator.isSyncingAll { break }
        }

        if dashboardPayload != nil {
            await loadPendingMeals()
            recordRefresh(reason: .pullToRefresh, outcome: .success, start: start)
        } else {
            errorMessage = "Refresh failed - using cached data"
            recordRefresh(reason: .pullToRefresh, outcome: .error, start: start)
        }

        isRefreshing = false
    }

    func foregroundRefresh(reason: RefreshReason = .foreground) {
        let start = CFAbsoluteTimeGetCurrent()
        lastRefreshReason = reason
        // isForegroundRefreshing is driven by coordinator.$isSyncingAll subscription

        if reason == .force {
            coordinator.syncAll(force: true)
        } else {
            coordinator.syncAll()
        }

        recordRefresh(reason: reason, outcome: .success, start: start)
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

            pendingMeals.removeAll { $0.id == meal.id }
        } catch {
            errorMessage = "Failed to save meal confirmation"
        }
    }

    // MARK: - Update After Logging

    func updateSummaryAfterLog(type: LogType, response: NexusResponse) {
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

        saveToStorage()

        addRecentLog(
            type: type,
            description: response.message ?? "Logged",
            calories: response.data?.calories,
            protein: response.data?.protein
        )

        lastSyncDate = Date()
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

        if recentLogs.count > 10 {
            recentLogs = Array(recentLogs.prefix(10))
        }

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
