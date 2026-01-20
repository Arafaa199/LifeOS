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

    private let api = NexusAPI.shared
    private let storage = SharedStorage.shared
    private let persistenceKey = "cached_summary"
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
        // Load from SharedStorage for widgets
        let cached = SharedStorage.DailySummary.current()
        summary.totalCalories = cached.calories
        summary.totalProtein = cached.protein
        summary.totalWater = cached.water
        summary.latestWeight = cached.weight
        lastSyncDate = cached.lastUpdate

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

    func loadTodaysSummary() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadTask = Task {
            guard !Task.isCancelled else { return }
            do {
                // Try to fetch from backend
                let response = try await api.fetchDailySummary()

                await MainActor.run {
                    if response.success, let data = response.data {
                        // Update summary from server
                        summary.totalCalories = data.calories
                        summary.totalProtein = data.protein
                        summary.totalWater = data.water
                        summary.latestWeight = data.weight
                        summary.weight = data.weight
                        summary.mood = data.mood
                        summary.energy = data.energy

                        // Update recent logs if provided
                        if let logs = data.logs {
                            recentLogs = logs.compactMap { logData -> LogEntry? in
                                let type = LogType(rawValue: logData.type) ?? .other
                                let timestamp = ISO8601DateFormatter().date(from: logData.timestamp) ?? Date()

                                return LogEntry(
                                    timestamp: timestamp,
                                    type: type,
                                    description: logData.description,
                                    calories: logData.calories,
                                    protein: logData.protein
                                )
                            }
                        }

                        // Save to SharedStorage for widgets
                        saveToStorage()
                    }
                    isLoading = false
                    lastSyncDate = Date()
                }
            } catch {
                // Fallback to cached data (already loaded in init)
                await MainActor.run {
                    isLoading = false
                    // Don't show error - we have cached data
                    // Just update timestamp to indicate we tried
                    lastSyncDate = Date()
                }
            }
        }
    }

    func refresh() async {
        isRefreshing = true

        // Reload from cache in case widgets updated it
        loadFromCache()

        try? await Task.sleep(nanoseconds: 300_000_000)

        await MainActor.run {
            isRefreshing = false
            lastSyncDate = Date()
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
