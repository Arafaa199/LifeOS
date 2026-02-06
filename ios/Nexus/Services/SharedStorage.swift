import Foundation

// Shared storage between app and widgets using App Groups
// Note: Requires App Group capability enabled in Xcode
// App Group ID: group.com.rfanw.nexus

// MARK: - Helper Extensions

fileprivate extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

fileprivate extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

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
        static let recentLogs = "recent_logs"
        static let goalCalories = "goal_calories"
        static let goalProtein = "goal_protein"
        static let goalWater = "goal_water"
        static let goalWeight = "goal_weight"
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

    // MARK: - Goals

    struct Goals {
        var calories: Int
        var protein: Double
        var water: Int
        var weight: Double?

        static let `default` = Goals(calories: 2000, protein: 150, water: 2500, weight: nil)
    }

    func getGoals() -> Goals {
        Goals(
            calories: defaults?.integer(forKey: Keys.goalCalories).nonZero ?? Goals.default.calories,
            protein: defaults?.double(forKey: Keys.goalProtein).nonZero ?? Goals.default.protein,
            water: defaults?.integer(forKey: Keys.goalWater).nonZero ?? Goals.default.water,
            weight: defaults?.double(forKey: Keys.goalWeight).nonZero
        )
    }

    func saveGoals(_ goals: Goals) {
        defaults?.set(goals.calories, forKey: Keys.goalCalories)
        defaults?.set(goals.protein, forKey: Keys.goalProtein)
        defaults?.set(goals.water, forKey: Keys.goalWater)
        if let weight = goals.weight {
            defaults?.set(weight, forKey: Keys.goalWeight)
        }
    }

    // MARK: - Save Methods

    func saveDailySummary(calories: Int, protein: Double, water: Int, weight: Double?) {
        defaults?.set(calories, forKey: Keys.todayCalories)
        defaults?.set(protein, forKey: Keys.todayProtein)
        defaults?.set(water, forKey: Keys.todayWater)
        if let weight = weight {
            defaults?.set(weight, forKey: Keys.todayWeight)
        }
        defaults?.set(Date(), forKey: Keys.lastUpdateDate)
    }

    func incrementWater(by amount: Int) {
        let current = getTodayWater()
        let new = current + amount
        defaults?.set(new, forKey: Keys.todayWater)
        defaults?.set(Date(), forKey: Keys.lastUpdateDate)
    }

    func addCalories(_ amount: Int, protein: Double) {
        let currentCal = getTodayCalories()
        let currentPro = getTodayProtein()
        defaults?.set(currentCal + amount, forKey: Keys.todayCalories)
        defaults?.set(currentPro + protein, forKey: Keys.todayProtein)
        defaults?.set(Date(), forKey: Keys.lastUpdateDate)
    }

    func saveRecentLog(type: String, description: String, calories: Int?, protein: Double?) {
        var logs = getRecentLogs()

        let log: [String: Any] = [
            "type": type,
            "description": description,
            "timestamp": Date().timeIntervalSince1970,
            "calories": calories ?? 0,
            "protein": protein ?? 0.0
        ]

        logs.insert(log, at: 0)

        // Keep only last 10 logs
        if logs.count > 10 {
            logs = Array(logs.prefix(10))
        }

        if let data = try? JSONSerialization.data(withJSONObject: logs) {
            defaults?.set(data, forKey: Keys.recentLogs)
        }
    }

    // MARK: - Get Methods

    func getTodayCalories() -> Int {
        checkAndResetIfNewDay()
        return defaults?.integer(forKey: Keys.todayCalories) ?? 0
    }

    func getTodayProtein() -> Double {
        checkAndResetIfNewDay()
        return defaults?.double(forKey: Keys.todayProtein) ?? 0.0
    }

    func getTodayWater() -> Int {
        checkAndResetIfNewDay()
        return defaults?.integer(forKey: Keys.todayWater) ?? 0
    }

    func getTodayWeight() -> Double? {
        defaults?.double(forKey: Keys.todayWeight)
    }

    func getRecentLogs() -> [[String: Any]] {
        guard let data = defaults?.data(forKey: Keys.recentLogs),
              let logs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return logs
    }

    func getLastUpdateDate() -> Date? {
        defaults?.object(forKey: Keys.lastUpdateDate) as? Date
    }

    // MARK: - Recovery Data (WHOOP)

    func saveRecoveryData(score: Int, hrv: Double?, rhr: Int?) {
        defaults?.set(score, forKey: Keys.recoveryScore)
        if let hrv = hrv {
            defaults?.set(hrv, forKey: Keys.recoveryHRV)
        }
        if let rhr = rhr {
            defaults?.set(rhr, forKey: Keys.recoveryRHR)
        }
        defaults?.set(Date(), forKey: Keys.recoveryDate)
    }

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
        return Constants.Dubai.isDateInToday(recoveryDate)
    }

    // MARK: - Fasting Data

    func saveFastingData(lastMealAt: Date?, isActive: Bool, startedAt: Date?) {
        if let lastMealAt = lastMealAt {
            defaults?.set(lastMealAt, forKey: Keys.fastingLastMealAt)
        }
        defaults?.set(isActive, forKey: Keys.fastingIsActive)
        if let startedAt = startedAt {
            defaults?.set(startedAt, forKey: Keys.fastingStartedAt)
        } else {
            defaults?.removeObject(forKey: Keys.fastingStartedAt)
        }
    }

    func saveFastingGoal(hours: Int) {
        defaults?.set(hours, forKey: Keys.fastingGoalHours)
    }

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

    func saveBudgetData(totalBudget: Double, spent: Double, remaining: Double, currency: String) {
        defaults?.set(totalBudget, forKey: Keys.budgetTotal)
        defaults?.set(spent, forKey: Keys.budgetSpent)
        defaults?.set(remaining, forKey: Keys.budgetRemaining)
        defaults?.set(currency, forKey: Keys.budgetCurrency)
    }

    func saveBudgetTopCategory(name: String, spent: Double, limit: Double) {
        defaults?.set(name, forKey: Keys.budgetTopCategory)
        defaults?.set(spent, forKey: Keys.budgetTopCategorySpent)
        defaults?.set(limit, forKey: Keys.budgetTopCategoryLimit)
    }

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

    // MARK: - Reset Methods

    func resetDailyStats() {
        defaults?.set(0, forKey: Keys.todayCalories)
        defaults?.set(0.0, forKey: Keys.todayProtein)
        defaults?.set(0, forKey: Keys.todayWater)
        defaults?.removeObject(forKey: Keys.todayWeight)
        defaults?.set(Date(), forKey: Keys.lastUpdateDate)
    }

    private func checkAndResetIfNewDay() {
        guard let lastUpdate = getLastUpdateDate() else {
            resetDailyStats()
            return
        }

        if !Constants.Dubai.isDateInToday(lastUpdate) {
            resetDailyStats()
        }
    }

    // MARK: - Clear All

    func clearAll() {
        guard let defaults = defaults else { return }
        defaults.dictionaryRepresentation().keys.forEach { key in
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Convenience Extensions

extension SharedStorage {
    struct DailySummary {
        let calories: Int
        let protein: Double
        let water: Int
        let weight: Double?
        let lastUpdate: Date?

        static func current() -> DailySummary {
            let storage = SharedStorage.shared
            return DailySummary(
                calories: storage.getTodayCalories(),
                protein: storage.getTodayProtein(),
                water: storage.getTodayWater(),
                weight: storage.getTodayWeight(),
                lastUpdate: storage.getLastUpdateDate()
            )
        }
    }
}
