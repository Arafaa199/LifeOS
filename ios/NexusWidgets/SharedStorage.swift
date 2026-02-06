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
}
