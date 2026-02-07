import SwiftUI

struct HealthFlatView: View {
    @StateObject private var viewModel = HealthViewModel()
    @State private var selectedPeriod: String = "7d"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    HealthTodayContent(viewModel: viewModel)

                    NexusSectionHeader(title: "Trends")
                        .padding(.horizontal)
                    HealthTrendsContent(viewModel: viewModel,
                                        selectedPeriod: $selectedPeriod,
                                        showFreshness: false)

                    NexusSectionHeader(title: "Insights")
                        .padding(.horizontal)
                    HealthInsightsContent(viewModel: viewModel)

                    Spacer(minLength: 40)
                }
            }
            .background(NexusTheme.Colors.background)
            .refreshable {
                await viewModel.fetchLocalHealthKit()
                SyncCoordinator.shared.syncAll(force: true)
                await viewModel.loadData()
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadData()
        }
    }
}
