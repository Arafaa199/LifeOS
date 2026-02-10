import SwiftUI
import UIKit

@main
struct NexusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.shared.scheduleHealthRefresh()
                // Sync pending music events before going to background
                if settings.musicLoggingEnabled {
                    Task { await MusicService.shared.syncPendingEvents() }
                }
            } else if newPhase == .active {
                SyncCoordinator.shared.syncAll(force: true)
                // Start music observer if enabled
                if settings.musicLoggingEnabled {
                    MusicService.shared.startObserving()
                }
            } else if newPhase == .inactive {
                // Stop observing when app becomes inactive
                if settings.musicLoggingEnabled {
                    MusicService.shared.stopObserving()
                }
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
        requestNotificationPermissionIfNeeded()

        // Resume significant location monitoring if enabled
        // (iOS relaunches app with .location key on significant change)
        if AppSettings.shared.locationTrackingEnabled {
            LocationTrackingService.shared.startTracking()
        }

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
        // Theme navigation bar color (warm cream light / rich dark with transparency)
        let themeNavBar = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "141210").withAlphaComponent(0.92)
                : UIColor(hex: "F4ECE4").withAlphaComponent(0.92)
        }

        // Tab bar - hide default (using custom ThemeTabBar)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().isHidden = true

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = themeNavBar
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "F2EDE8")
                    : UIColor(hex: "1A1410")
            }
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "F2EDE8")
                    : UIColor(hex: "1A1410")
            }
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(hex: "FF005E")

        // Accent color for controls
        UIView.appearance().tintColor = UIColor(hex: "FF005E")
    }

    private func requestNotificationPermissionIfNeeded() {
        let hasRequestedKey = "hasRequestedNotificationPermission"
        guard !UserDefaults.standard.bool(forKey: hasRequestedKey) else { return }

        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                UserDefaults.standard.set(true, forKey: hasRequestedKey)
            }
        }
    }
}
