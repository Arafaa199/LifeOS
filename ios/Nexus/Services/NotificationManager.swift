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

    // Fasting milestone hours to notify
    private let fastingMilestones: [Int] = [12, 16, 18, 20, 24]

    // MARK: - Notification Identifiers

    private enum NotificationID {
        static let budgetAlert = "com.nexus.budget-alert"
        static let fastingMilestone = "com.nexus.fasting-milestone"
    }

    // MARK: - Notification Categories

    private enum NotificationCategory {
        static let fasting = "FASTING_MILESTONE"
    }

    private init() {
        registerCategories()
    }

    private func registerCategories() {
        let breakFastAction = UNNotificationAction(
            identifier: "BREAK_FAST",
            title: "Break Fast",
            options: [.foreground]
        )

        let continueAction = UNNotificationAction(
            identifier: "CONTINUE_FAST",
            title: "Keep Going",
            options: []
        )

        let fastingCategory = UNNotificationCategory(
            identifier: NotificationCategory.fasting,
            actions: [continueAction, breakFastAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([fastingCategory])
    }

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

    // MARK: - Fasting Notifications

    /// Schedule notifications for fasting milestones when a fast starts
    /// - Parameter startTime: When the fast began
    func scheduleFastingMilestones(startTime: Date) async {
        guard await isAuthorized else {
            logger.debug("[notifications] skipping fasting schedule — not authorized")
            return
        }

        // Cancel any existing fasting notifications first
        await cancelFastingNotifications()

        let now = Date()

        for hours in fastingMilestones {
            let milestoneTime = startTime.addingTimeInterval(TimeInterval(hours * 3600))

            // Only schedule if milestone is in the future
            guard milestoneTime > now else {
                logger.debug("[notifications] skipping \(hours)h milestone — already passed")
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "Fasting Milestone 🎉"
            content.body = fastingMilestoneMessage(hours: hours)
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.fasting
            content.threadIdentifier = "fasting"
            content.userInfo = [
                "type": "fasting_milestone",
                "hours": hours
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: milestoneTime.timeIntervalSince(now),
                repeats: false
            )

            let identifier = "\(NotificationID.fastingMilestone)-\(hours)h"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
                logger.info("[notifications] scheduled fasting milestone: \(hours)h at \(milestoneTime)")
            } catch {
                logger.error("[notifications] failed to schedule fasting milestone: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel all pending fasting notifications (called when fast ends)
    func cancelFastingNotifications() async {
        let identifiers = fastingMilestones.map { "\(NotificationID.fastingMilestone)-\($0)h" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        logger.debug("[notifications] cancelled fasting notifications")
    }

    private func fastingMilestoneMessage(hours: Int) -> String {
        switch hours {
        case 12:
            return "You've been fasting for 12 hours! Fat burning is ramping up."
        case 16:
            return "16 hours! Autophagy is kicking in. Great progress!"
        case 18:
            return "18 hours of fasting! Your body is in deep ketosis."
        case 20:
            return "20 hours! You're in the optimization zone. Amazing discipline!"
        case 24:
            return "24 hours! A full day of fasting. Incredible achievement!"
        default:
            return "You've been fasting for \(hours) hours. Keep going!"
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
