import SwiftUI
import UIKit

@main
struct NexusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.shared.scheduleHealthRefresh()
            } else if newPhase == .active {
                SyncCoordinator.shared.syncAll(force: true)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        KeychainManager.shared.migrateFromUserDefaultsIfNeeded()
        BackgroundTaskManager.shared.registerBackgroundTasks()
        configureAppearance()
        QuickActionManager.shared.registerShortcuts()

        // Handle quick action if app was launched from a shortcut
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            QuickActionManager.shared.handleShortcutItem(shortcutItem)
        }

        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Handle quick action when app is already running
        let handled = QuickActionManager.shared.handleShortcutItem(shortcutItem)
        completionHandler(handled)
    }

    private func configureAppearance() {
        let warmBg = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.systemBackground
                : UIColor(red: 0.894, green: 0.835, blue: 0.765, alpha: 1.0)
        }

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = warmBg
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = warmBg
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
}
