import Foundation
import SwiftUI
import WidgetKit
import Combine
import os

@MainActor
class DashboardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "dashboard")
    @Published var summary = DailySummary()
    @Published var recentLogs: [LogEntry] = []
    @Published var errorMessage: String?
    @Published var lastSyncDate: Date?

    @Published var dashboardPayload: DashboardPayload?
    @Published var dataSource: DashboardResult.DataSource?
    @Published var lastUpdatedFormatted: String?

    // Meal confirmations
    @Published var pendingMeals: [InferredMeal] = []

    private let dashboardService: DashboardService
    private let coordinator: SyncCoordinator
    private let api: NexusAPI
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Sync State (derived from coordinator)

    var isLoading: Bool {
        coordinator.domainStates[.dashboard]?.isSyncing == true
    }

    var isForegroundRefreshing: Bool {
        coordinator.isSyncingAll
    }

    var foregroundRefreshFailed: Bool {
        coordinator.domainStates[.dashboard]?.lastError != nil
    }

    var isDataStale: Bool {
        coordinator.domainStates[.dashboard]?.staleness != .fresh
    }

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

    var isRefreshing: Bool {
        coordinator.isSyncingAll
    }

    /// True if dashboard data is from cache (not fresh from network)
    var isFromCache: Bool {
        dataSource == .cache
    }

    /// Label showing data source for UI
    var dataSourceLabel: String {
        switch dataSource {
        case .network: return "Live"
        case .cache: return "Cached"
        case .none: return ""
        }
    }

    /// True if dashboard data is for a different day than today (Dubai timezone)
    var isDataFromYesterday: Bool {
        guard let payload = dashboardPayload else { return false }
        return !payload.meta.isForToday
    }

    /// Human-readable description of data staleness
    var dataStalenessDescription: String? {
        guard let payload = dashboardPayload else { return nil }
        if !payload.meta.isForToday {
            return "Data is from \(payload.meta.forDate) (not today)"
        }
        if payload.meta.isDataOld && isFromCache {
            return "Cached data - pull to refresh"
        }
        return nil
    }

    private let storage = SharedStorage.shared

    init(
        dashboardService: DashboardService? = nil,
        coordinator: SyncCoordinator? = nil,
        api: NexusAPI? = nil
    ) {
        self.dashboardService = dashboardService ?? DashboardService.shared
        self.coordinator = coordinator ?? SyncCoordinator.shared
        self.api = api ?? NexusAPI.shared
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

        // Subscribe to dashboard-specific state changes only
        // (isLoading, isForegroundRefreshing, etc.) trigger view updates.
        coordinator.dashboardStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Also subscribe to isSyncingAll changes for foreground refresh indicator
        coordinator.$isSyncingAll
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func handlePayloadUpdate(_ payload: DashboardPayload) {
        logger.debug("Payload update: todayFacts=\(payload.todayFacts != nil ? "present" : "nil"), recovery=\(payload.todayFacts?.recoveryScore ?? -1)")

        dashboardPayload = payload

        // Get actual source from coordinator domain state
        if let domainState = coordinator.domainStates[SyncCoordinator.SyncDomain.dashboard] {
            dataSource = domainState.isFromCache ? DashboardResult.DataSource.cache : DashboardResult.DataSource.network
            lastSyncDate = domainState.lastSuccessDate ?? Date()
        } else {
            dataSource = DashboardResult.DataSource.network
            lastSyncDate = Date()
        }
        lastUpdatedFormatted = RelativeDateTimeFormatter().localizedString(for: lastSyncDate ?? Date(), relativeTo: Date())

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
    }

    // MARK: - Load Data

    private func loadFromCache() {
        if let cachedResult = dashboardService.loadCached() {
            dashboardPayload = cachedResult.payload
            dataSource = cachedResult.source
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
        summary.totalCalories = payload.todayFacts?.caloriesConsumed ?? 0
        summary.totalWater = payload.todayFacts?.waterMl ?? 0
        summary.latestWeight = payload.todayFacts?.weightKg
        summary.weight = payload.todayFacts?.weightKg
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
        errorMessage = nil

        coordinator.syncAll(force: true)

        // Wait for sync completion using Combine with timeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            var resumed = false

            // Timeout after 15 seconds
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if !resumed {
                    resumed = true
                    cancellable?.cancel()
                    continuation.resume()
                }
            }

            cancellable = coordinator.$isSyncingAll
                .filter { !$0 }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    if !resumed {
                        resumed = true
                        timeoutTask.cancel()
                        continuation.resume()
                    }
                }
        }

        if dashboardPayload != nil {
            await loadPendingMeals()
        } else {
            errorMessage = "Refresh failed - using cached data"
        }
    }

    func foregroundRefresh(force: Bool = false) {
        coordinator.syncAll(force: force)
    }

    func forceRefresh() {
        foregroundRefresh(force: true)
    }

    func loadPendingMeals() async {
        do {
            pendingMeals = try await api.fetchPendingMealConfirmations()
        } catch {
            logger.error("Failed to load pending meals: \(error.localizedDescription)")
            pendingMeals = []
        }
    }

    func confirmMeal(_ meal: InferredMeal, action: String) async {
        do {
            let response = try await api.confirmMeal(
                mealDate: meal.mealDate,
                mealTime: meal.mealTime,
                mealType: meal.mealType,
                action: action
            )

            if response.success {
                pendingMeals.removeAll { $0.id == meal.id }
            } else {
                errorMessage = response.message ?? "Failed to save meal confirmation"
            }
        } catch {
            errorMessage = "Failed to save meal confirmation"
            logger.error("confirmMeal error: \(error.localizedDescription)")
        }
    }

    // MARK: - Fasting

    func startFast() async throws {
        let response = try await api.startFast()
        if response.effectiveSuccess {
            // Schedule fasting milestone notifications
            await NotificationManager.shared.scheduleFastingMilestones(startTime: Date())
        }
        await refresh()
    }

    func breakFast() async throws {
        _ = try await api.breakFast()
        // Cancel any pending fasting notifications
        await NotificationManager.shared.cancelFastingNotifications()
        await refresh()
    }

    // MARK: - Universal Logging

    func logUniversal(_ text: String) async throws -> NexusResponse {
        let (response, result) = await api.logUniversalOffline(text)

        if case .failed(let error) = result {
            throw error
        }

        if let response = response {
            updateSummaryAfterLog(type: .note, response: response)
            return response
        }

        // Queued for offline sync
        return NexusResponse(success: true, message: "Queued for sync", data: nil)
    }

    // MARK: - Update After Logging

    func updateSummaryAfterLog(type: LogType, response: NexusResponse) {
        if let data = response.data {
            if let calories = data.calories {
                summary.totalCalories = calories
            }
            if let protein = data.protein {
                summary.totalProtein = protein
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
