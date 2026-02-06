import Foundation

// Minimal SharedStorage for widget extension - read-only from App Group
// Full version is in main app: Nexus/Services/SharedStorage.swift

class SharedStorage {
    static let shared = SharedStorage()

    private let appGroupID = "group.com.rfanw.nexus"
    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Keys

    private enum Keys {
        static let todayCalories = "today_calories"
        static let todayProtein = "today_protein"
        static let todayWater = "today_water"
        static let todayWeight = "today_weight"
        static let lastUpdateDate = "last_update_date"
        static let recoveryScore = "recovery_score"
        static let recoveryHRV = "recovery_hrv"
        static let recoveryRHR = "recovery_rhr"
        static let recoveryDate = "recovery_date"
        static let fastingLastMealAt = "fasting_last_meal_at"
        static let fastingIsActive = "fasting_is_active"
        static let fastingStartedAt = "fasting_started_at"
        static let fastingGoalHours = "fasting_goal_hours"
        static let budgetTotal = "budget_total"
        static let budgetSpent = "budget_spent"
        static let budgetRemaining = "budget_remaining"
        static let budgetCurrency = "budget_currency"
        static let budgetTopCategory = "budget_top_category"
        static let budgetTopCategorySpent = "budget_top_category_spent"
        static let budgetTopCategoryLimit = "budget_top_category_limit"
    }

    // MARK: - Recovery Data (WHOOP)

    func getRecoveryScore() -> Int? {
        guard isRecoveryDataCurrent() else { return nil }
        let score = defaults?.integer(forKey: Keys.recoveryScore) ?? 0
        return score > 0 ? score : nil
    }

    func getRecoveryHRV() -> Double? {
        guard isRecoveryDataCurrent() else { return nil }
        let hrv = defaults?.double(forKey: Keys.recoveryHRV) ?? 0
        return hrv > 0 ? hrv : nil
    }

    func getRecoveryRHR() -> Int? {
        guard isRecoveryDataCurrent() else { return nil }
        let rhr = defaults?.integer(forKey: Keys.recoveryRHR) ?? 0
        return rhr > 0 ? rhr : nil
    }

    func getRecoveryDate() -> Date? {
        defaults?.object(forKey: Keys.recoveryDate) as? Date
    }

    private func isRecoveryDataCurrent() -> Bool {
        guard let recoveryDate = getRecoveryDate() else { return false }
        return Calendar.current.isDateInToday(recoveryDate)
    }

    // MARK: - Daily Summary

    func getTodayCalories() -> Int {
        defaults?.integer(forKey: Keys.todayCalories) ?? 0
    }

    func getTodayProtein() -> Double {
        defaults?.double(forKey: Keys.todayProtein) ?? 0.0
    }

    func getTodayWater() -> Int {
        defaults?.integer(forKey: Keys.todayWater) ?? 0
    }

    func getTodayWeight() -> Double? {
        let weight = defaults?.double(forKey: Keys.todayWeight) ?? 0
        return weight > 0 ? weight : nil
    }

    func getLastUpdateDate() -> Date? {
        defaults?.object(forKey: Keys.lastUpdateDate) as? Date
    }

    // MARK: - Fasting Data

    func getLastMealTime() -> Date? {
        defaults?.object(forKey: Keys.fastingLastMealAt) as? Date
    }

    func isFastingActive() -> Bool {
        defaults?.bool(forKey: Keys.fastingIsActive) ?? false
    }

    func getFastingStartedAt() -> Date? {
        defaults?.object(forKey: Keys.fastingStartedAt) as? Date
    }

    func getFastingGoalHours() -> Int {
        let goal = defaults?.integer(forKey: Keys.fastingGoalHours) ?? 0
        return goal > 0 ? goal : 16  // Default to 16h IF
    }

    /// Hours elapsed since last meal (for passive IF tracking)
    func getHoursSinceLastMeal() -> Double? {
        guard let lastMeal = getLastMealTime() else { return nil }
        return Date().timeIntervalSince(lastMeal) / 3600.0
    }

    /// Hours elapsed in active fasting session
    func getFastingElapsedHours() -> Double? {
        guard isFastingActive(), let startedAt = getFastingStartedAt() else { return nil }
        return Date().timeIntervalSince(startedAt) / 3600.0
    }

    // MARK: - Budget Data

    func getBudgetTotal() -> Double {
        defaults?.double(forKey: Keys.budgetTotal) ?? 0
    }

    func getBudgetSpent() -> Double {
        defaults?.double(forKey: Keys.budgetSpent) ?? 0
    }

    func getBudgetRemaining() -> Double {
        defaults?.double(forKey: Keys.budgetRemaining) ?? 0
    }

    func getBudgetCurrency() -> String {
        defaults?.string(forKey: Keys.budgetCurrency) ?? "AED"
    }

    func getBudgetTopCategory() -> (name: String, spent: Double, limit: Double)? {
        guard let name = defaults?.string(forKey: Keys.budgetTopCategory),
              !name.isEmpty else { return nil }
        let spent = defaults?.double(forKey: Keys.budgetTopCategorySpent) ?? 0
        let limit = defaults?.double(forKey: Keys.budgetTopCategoryLimit) ?? 0
        return (name, spent, limit)
    }

    /// Progress ratio (0.0 to 1.0+) for budget usage
    func getBudgetProgress() -> Double {
        let total = getBudgetTotal()
        guard total > 0 else { return 0 }
        return getBudgetSpent() / total
    }
}
