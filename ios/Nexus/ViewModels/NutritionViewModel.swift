import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "nutrition")

@MainActor
class NutritionViewModel: ObservableObject {
    @Published var foodEntries: [FoodLogEntry] = []
    @Published var waterEntries: [WaterLogEntry] = []
    @Published var dailyTotals: NutritionTotals?
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalWaterToday: Int = 0

    private let api = NexusAPI.shared
    static let waterGoalMl = 3000

    var waterProgress: Double {
        guard totalWaterToday > 0 else { return 0 }
        return min(Double(totalWaterToday) / Double(Self.waterGoalMl), 1.0)
    }

    var waterProgressText: String {
        "\(totalWaterToday) / \(Self.waterGoalMl) ml"
    }

    func loadHistory(for date: Date? = nil) async {
        isLoading = true
        errorMessage = nil

        let targetDate = date ?? selectedDate
        let dateString = NexusAPI.dubaiDateString(from: targetDate)

        do {
            let response = try await api.fetchNutritionHistory(date: dateString)
            foodEntries = response.food_log
            waterEntries = response.water_log
            dailyTotals = response.totals
            totalWaterToday = response.totals.water_ml
            logger.debug("Loaded nutrition history for \(dateString): \(response.totals.meals_logged) meals, \(response.totals.water_ml)ml water")
        } catch {
            logger.error("Failed to load nutrition history: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func setDate(_ date: Date) {
        selectedDate = date
        Task {
            await loadHistory(for: date)
        }
    }

    var foodEntriesByMeal: [(String, [FoodLogEntry])] {
        let mealOrder = ["Breakfast", "Lunch", "Dinner", "Snack"]
        var grouped: [String: [FoodLogEntry]] = [:]

        for entry in foodEntries {
            let meal = entry.mealTypeDisplay
            grouped[meal, default: []].append(entry)
        }

        return mealOrder.compactMap { meal in
            guard let entries = grouped[meal], !entries.isEmpty else { return nil }
            return (meal, entries)
        }
    }
}
