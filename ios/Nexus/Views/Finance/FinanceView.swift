import SwiftUI

struct FinanceView: View {
    @StateObject private var viewModel = FinanceViewModel()
    @State private var selectedTab = 0
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Picker
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
                            VStack(spacing: 6) {
                                Image(systemName: tabIcon(for: index))
                                    .font(.system(size: 18, weight: selectedTab == index ? .semibold : .regular))
                                Text(tabTitle(for: index))
                                    .font(.caption2)
                                    .fontWeight(selectedTab == index ? .semibold : .regular)
                            }
                            .foregroundColor(selectedTab == index ? .nexusFinance : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == index ?
                                Color.nexusFinance.opacity(0.1) :
                                Color.clear
                            )
                        }
                    }
                }
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .fill(Color(.separator).opacity(0.3))
                        .frame(height: 1),
                    alignment: .bottom
                )

                // Tab Content
                TabView(selection: $selectedTab) {
                    QuickExpenseView(viewModel: viewModel)
                        .tag(0)

                    TransactionsListView(viewModel: viewModel)
                        .tag(1)

                    BudgetView(viewModel: viewModel)
                        .tag(2)

                    InstallmentsView(viewModel: viewModel)
                        .tag(3)

                    InsightsView(viewModel: viewModel)
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Finance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.nexusFinance)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.triggerSMSImport()
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.nexusFinance)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                FinancePlanningView()
            }
        }
    }

    private func tabIcon(for index: Int) -> String {
        switch index {
        case 0: return selectedTab == 0 ? "bolt.fill" : "bolt"
        case 1: return selectedTab == 1 ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
        case 2: return selectedTab == 2 ? "chart.bar.fill" : "chart.bar"
        case 3: return selectedTab == 3 ? "creditcard.fill" : "creditcard"
        case 4: return selectedTab == 4 ? "lightbulb.fill" : "lightbulb"
        default: return "circle"
        }
    }

    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "Quick"
        case 1: return "History"
        case 2: return "Budget"
        case 3: return "BNPL"
        case 4: return "Insights"
        default: return ""
        }
    }
}

#Preview {
    FinanceView()
}
