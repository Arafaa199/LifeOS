import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var financeViewModel = FinanceViewModel()
    @StateObject private var documentsViewModel = DocumentsViewModel()
    @State private var selectedTab = 0

    // Failed item alert state
    @State private var showingFailedItemAlert = false
    @State private var failedItemDescription = ""
    @State private var failedItemError = ""

    var body: some View {
        VStack(spacing: 0) {
            // Offline indicator at the top
            OfflineBannerView()

            TabView(selection: $selectedTab) {
                TodayView(viewModel: viewModel)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house")
                }
                .tag(0)

                QuickLogView(viewModel: viewModel)
                    .tabItem {
                        Label("Log", systemImage: selectedTab == 1 ? "plus.circle.fill" : "plus.circle")
                    }
                    .tag(1)

                HealthView()
                    .tabItem {
                        Label("Health", systemImage: selectedTab == 2 ? "heart.fill" : "heart")
                    }
                    .tag(2)

                FinanceView(viewModel: financeViewModel)
                    .tabItem {
                        Label("Finance", systemImage: selectedTab == 3 ? "chart.pie.fill" : "chart.pie")
                    }
                    .tag(3)

                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: selectedTab == 4 ? "calendar.circle.fill" : "calendar.circle")
                    }
                    .tag(4)

                NavigationView {
                    DocumentsListView(viewModel: documentsViewModel)
                        .navigationTitle("Documents")
                }
                .tabItem {
                    Label("Documents", systemImage: selectedTab == 5 ? "doc.text.fill" : "doc.text")
                }
                .tag(5)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: selectedTab == 6 ? "gearshape.fill" : "gearshape")
                    }
                    .tag(6)
            }
            .tint(.nexusPrimary)
            .environmentObject(viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .offlineItemPermanentlyFailed)) { notification in
            if let description = notification.userInfo?["description"] as? String,
               let error = notification.userInfo?["error"] as? String {
                failedItemDescription = description
                failedItemError = error
                showingFailedItemAlert = true
            }
        }
        .alert("Sync Failed", isPresented: $showingFailedItemAlert) {
            Button("View in Settings") {
                selectedTab = 6  // Settings tab
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("\"\(failedItemDescription)\" could not be synced after multiple attempts.\n\nError: \(failedItemError)\n\nGo to Settings → Sync Issues to retry or discard.")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings.shared)
}
