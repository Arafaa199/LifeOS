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
}
