import Foundation

// Shared storage between app and widgets using App Groups
// Note: Requires App Group capability enabled in Xcode
// Format: group.com.yourdomain.nexus

class SharedStorage {
    static let shared = SharedStorage()

    private let appGroupID = "group.com.yourdomain.nexus"
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

        let calendar = Calendar.current
        if !calendar.isDateInToday(lastUpdate) {
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
