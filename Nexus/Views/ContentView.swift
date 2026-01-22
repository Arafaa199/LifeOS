import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if settings.useDashboardV2 {
                    DashboardV2View(viewModel: viewModel)
                } else {
                    DashboardView(viewModel: viewModel)
                }
            }
            .tabItem {
                Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house")
            }
            .tag(0)

            QuickLogView(viewModel: viewModel)
                .tabItem {
                    Label("Log", systemImage: selectedTab == 1 ? "plus.circle.fill" : "plus.circle")
                }
                .tag(1)

            FoodLogView(viewModel: viewModel)
                .tabItem {
                    Label("Food", systemImage: selectedTab == 2 ? "fork.knife.circle.fill" : "fork.knife")
                }
                .tag(2)

            FinanceView()
                .tabItem {
                    Label("Finance", systemImage: selectedTab == 3 ? "chart.pie.fill" : "chart.pie")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: selectedTab == 4 ? "gearshape.fill" : "gearshape")
                }
                .tag(4)
        }
        .tint(.nexusPrimary)
        .environmentObject(viewModel)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
