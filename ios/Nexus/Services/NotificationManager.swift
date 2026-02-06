import Foundation
import UserNotifications
import os

class NotificationManager {
    static let shared = NotificationManager()

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "notifications")
    private let center = UNUserNotificationCenter.current()

    // Track which budgets we've already alerted for today (prevent spam)
    private var alertedBudgetsToday: Set<String> = []
    private var lastAlertResetDate: Date?

    // MARK: - Notification Identifiers

    private enum NotificationID {
        static let budgetAlert = "com.nexus.budget-alert"
    }

    private init() {}

    // MARK: - Permission

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("[notifications] authorization granted: \(granted)")
            return granted
        } catch {
            logger.error("[notifications] authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Budget Alerts

    /// Check budgets and send alerts if any exceed 80% threshold
    /// Called after dashboard sync completes
    func checkBudgetAlerts(budgets: [Budget], categorySpending: [String: Double]) async {
        resetAlertsIfNewDay()

        guard await isAuthorized else {
            logger.debug("[notifications] skipping budget check — not authorized")
            return
        }

        let threshold: Double = 0.8 // 80%

        for budget in budgets {
            let category = budget.category
            let budgetAmount = budget.budgetAmount
            guard budgetAmount > 0 else { continue }

            // Get spending for this category (already absolute value)
            let spent = categorySpending[category] ?? budget.spent ?? 0
            let usageRatio = spent / budgetAmount

            // Skip if we've already alerted for this category today
            guard !alertedBudgetsToday.contains(category) else { continue }

            if usageRatio >= threshold {
                await sendBudgetAlert(
                    category: category,
                    spent: spent,
                    budget: budgetAmount,
                    percentage: Int(usageRatio * 100)
                )
                alertedBudgetsToday.insert(category)
            }
        }
    }

    private func sendBudgetAlert(category: String, spent: Double, budget: Double, percentage: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Budget Alert"
        content.body = "\(category) at \(percentage)% (\(formatCurrency(spent, currency: "AED")) of \(formatCurrency(budget, currency: "AED")))"
        content.sound = .default
        content.categoryIdentifier = "BUDGET_ALERT"
        content.userInfo = [
            "type": "budget_alert",
            "category": category,
            "spent": spent,
            "budget": budget,
            "percentage": percentage
        ]

        // Add thread identifier for grouping
        content.threadIdentifier = "budget-alerts"

        let identifier = "\(NotificationID.budgetAlert)-\(category)-\(Constants.Dubai.dateString(from: Date()))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
            logger.info("[notifications] sent budget alert: \(category) at \(percentage)%")
        } catch {
            logger.error("[notifications] failed to send budget alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Daily Reset

    private func resetAlertsIfNewDay() {
        let today = Constants.Dubai.dateString(from: Date())
        let lastReset = lastAlertResetDate.map { Constants.Dubai.dateString(from: $0) }

        if lastReset != today {
            alertedBudgetsToday.removeAll()
            lastAlertResetDate = Date()
            logger.debug("[notifications] reset daily alert tracking")
        }
    }

    // MARK: - Badge Management

    func clearBadge() async {
        do {
            try await center.setBadgeCount(0)
        } catch {
            logger.warning("[notifications] failed to clear badge: \(error.localizedDescription)")
        }
    }
}
