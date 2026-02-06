import UIKit
import SwiftUI
import Combine

/// Manages home screen quick actions (3D Touch / long-press on app icon)
@MainActor
final class QuickActionManager: ObservableObject {
    static let shared = QuickActionManager()

    /// The pending quick action to execute when app becomes active
    @Published var pendingAction: QuickActionType?

    private init() {}

    // MARK: - Quick Action Types

    enum QuickActionType: String {
        case logWater = "com.nexus.quickaction.logwater"
        case logMood = "com.nexus.quickaction.logmood"
        case startFast = "com.nexus.quickaction.startfast"

        var shortcutItem: UIApplicationShortcutItem {
            switch self {
            case .logWater:
                return UIApplicationShortcutItem(
                    type: rawValue,
                    localizedTitle: "Log Water",
                    localizedSubtitle: "Add 250ml",
                    icon: UIApplicationShortcutIcon(systemImageName: "drop.fill"),
                    userInfo: nil
                )
            case .logMood:
                return UIApplicationShortcutItem(
                    type: rawValue,
                    localizedTitle: "Log Mood",
                    localizedSubtitle: "How are you feeling?",
                    icon: UIApplicationShortcutIcon(systemImageName: "face.smiling"),
                    userInfo: nil
                )
            case .startFast:
                return UIApplicationShortcutItem(
                    type: rawValue,
                    localizedTitle: "Start Fast",
                    localizedSubtitle: "Begin fasting session",
                    icon: UIApplicationShortcutIcon(systemImageName: "timer"),
                    userInfo: nil
                )
            }
        }
    }

    // MARK: - Registration

    /// Register all quick actions on the home screen
    func registerShortcuts() {
        UIApplication.shared.shortcutItems = [
            QuickActionType.logWater.shortcutItem,
            QuickActionType.logMood.shortcutItem,
            QuickActionType.startFast.shortcutItem
        ]
    }

    // MARK: - Handling

    /// Handle a shortcut item selection
    /// - Parameter shortcutItem: The selected shortcut item
    /// - Returns: true if handled successfully
    @discardableResult
    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let actionType = QuickActionType(rawValue: shortcutItem.type) else {
            return false
        }

        pendingAction = actionType
        return true
    }

    /// Execute the pending action and clear it
    func executePendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action {
        case .logWater:
            await executeLogWater()
        case .logMood:
            // Mood requires user input - just navigate to Health tab
            // The pending action will be observed by ContentView
            break
        case .startFast:
            await executeStartFast()
        }
    }

    // MARK: - Action Execution

    private func executeLogWater() async {
        do {
            let response = try await NexusAPI.shared.logWater(amountML: 250)
            if response.success {
                showNotification(title: "Water Logged", body: "Added 250ml of water")
            }
        } catch {
            showNotification(title: "Failed", body: "Could not log water")
        }
    }

    private func executeStartFast() async {
        do {
            let response = try await NexusAPI.shared.startFast()
            if response.effectiveSuccess {
                showNotification(title: "Fast Started", body: "Your fasting session has begun")
            } else {
                let errorMsg = response.error ?? "Unknown error"
                showNotification(title: "Fast Failed", body: errorMsg)
            }
        } catch {
            showNotification(title: "Failed", body: "Could not start fast")
        }
    }

    private func showNotification(title: String, body: String) {
        // Post a local notification banner (using NotificationCenter for in-app feedback)
        NotificationCenter.default.post(
            name: .quickActionCompleted,
            object: nil,
            userInfo: ["title": title, "body": body]
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let quickActionCompleted = Notification.Name("quickActionCompleted")
}
