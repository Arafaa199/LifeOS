import SwiftUI

struct FinanceFlatView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingSettings = false
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    FinanceOverviewContent(
                        viewModel: viewModel,
                        onAddExpense: { showingAddExpense = true },
                        onAddIncome: { showingAddIncome = true }
                    )

                    NavigationLink(destination: FinanceActivityView(viewModel: viewModel)) {
                        HStack {
                            Text("All Transactions")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                        .padding(NexusTheme.Spacing.lg)
                        .background(NexusTheme.Colors.card)
                        .cornerRadius(NexusTheme.Radius.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, NexusTheme.Spacing.md)

                    ThemeSectionHeader(title: "Plan")
                        .padding(.horizontal)
                        .padding(.top, NexusTheme.Spacing.lg)

                    NavigationLink(destination: FinancePlanningView()) {
                        HStack {
                            Text("Finance Settings")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                        .padding(NexusTheme.Spacing.lg)
                        .background(NexusTheme.Colors.card)
                        .cornerRadius(NexusTheme.Radius.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .background(NexusTheme.Colors.background)
            .refreshable {
                await viewModel.refresh()
            }
            .navigationTitle("Finance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                    }
                    .accessibilityLabel("Finance settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                FinancePlanningView()
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddIncome) {
                IncomeView(viewModel: viewModel)
            }
        }
    }
}
