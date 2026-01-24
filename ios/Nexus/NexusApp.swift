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

    @Published var useDashboardV2: Bool {
        didSet {
            UserDefaults.standard.set(useDashboardV2, forKey: "useDashboardV2")
        }
    }

    init() {
        self.webhookBaseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
        self.useDashboardV2 = UserDefaults.standard.bool(forKey: "useDashboardV2")
    }
}
