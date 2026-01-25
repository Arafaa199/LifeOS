import SwiftUI
import Combine
import UIKit

@main
struct NexusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings()
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
                // Sync HealthKit data when app comes to foreground
                Task {
                    try? await HealthKitSyncService.shared.syncAllData()
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

class AppSettings: ObservableObject {
    @Published var webhookBaseURL: String {
        didSet {
            UserDefaults.standard.set(webhookBaseURL, forKey: "webhookBaseURL")
        }
    }

    init() {
        self.webhookBaseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
    }
}
