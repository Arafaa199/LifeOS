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
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.nexusFinance)
                        .padding()
                        .background(Color.nexusCardBackground)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    NexusSectionHeader(title: "Plan")
                        .padding(.horizontal)
                        .padding(.top, 16)

                    NavigationLink(destination: FinancePlanningView()) {
                        HStack {
                            Text("Finance Settings")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.nexusFinance)
                        .padding()
                        .background(Color.nexusCardBackground)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.nexusBackground)
            .refreshable {
                await viewModel.refresh()
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
