import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var financeViewModel = FinanceViewModel()
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

                HealthFlatView()
                    .tabItem {
                        Label("Health", systemImage: selectedTab == 1 ? "heart.fill" : "heart")
                    }
                    .tag(1)

                FinanceFlatView(viewModel: financeViewModel)
                    .tabItem {
                        Label("Finance", systemImage: selectedTab == 2 ? "chart.pie.fill" : "chart.pie")
                    }
                    .tag(2)

                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: selectedTab == 3 ? "calendar.circle.fill" : "calendar.circle")
                    }
                    .tag(3)

                MoreView()
                    .tabItem {
                        Label("More", systemImage: selectedTab == 4 ? "ellipsis.circle.fill" : "ellipsis.circle")
                    }
                    .tag(4)
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
            Button("Review in Settings") {
                selectedTab = 4  // More tab (Settings is inside)
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The following item failed to sync after multiple attempts:")
                    .fontWeight(.medium)

                Text("\"\(failedItemDescription)\"")
                    .italic()

                Text("Error:")
                    .fontWeight(.medium)
                    .padding(.top, 4)

                Text(failedItemError)
                    .font(.caption)

                Text("Go to More → Settings → Sync Status to retry or discard this item.")
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings.shared)
}
