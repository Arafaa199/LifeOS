import SwiftUI
import Combine

@main
struct NexusApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
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
