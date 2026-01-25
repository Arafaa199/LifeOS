import SwiftUI
import Combine
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
                // Sync HealthKit and Calendar data when app comes to foreground
                Task {
                    try? await HealthKitSyncService.shared.syncAllData()
                    try? await CalendarSyncService.shared.syncAllData()
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
        BackgroundTaskManager.shared.registerBackgroundTasks()
        return true
    }
}
