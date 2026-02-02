import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var documentsViewModel = DocumentsViewModel()
    @State private var selectedTab = 0

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

                FinanceView()
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings.shared)
}
