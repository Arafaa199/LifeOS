import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(0)

            QuickLogView(viewModel: viewModel)
                .tabItem {
                    Label("Quick Log", systemImage: "plus.circle.fill")
                }
                .tag(1)

            FoodLogView(viewModel: viewModel)
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .environmentObject(viewModel)
    }
}

#Preview {
    ContentView()
}
