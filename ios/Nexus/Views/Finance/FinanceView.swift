import SwiftUI
import Combine

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedSegment = 0
    @State private var showingSettings = false
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("", selection: $selectedSegment) {
                    Text("Overview").tag(0)
                    Text("Activity").tag(1)
                    Text("Plan").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Content
                TabView(selection: $selectedSegment) {
                    FinanceOverviewView(
                        viewModel: viewModel,
                        onAddExpense: { showingAddExpense = true },
                        onAddIncome: { showingAddIncome = true }
                    )
                    .tag(0)

                    FinanceActivityView(viewModel: viewModel)
                        .tag(1)

                    FinancePlanContent()
                        .tag(2)
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

// MARK: - Overview Screen

struct FinanceOverviewView: View {
    @ObservedObject var viewModel: FinanceViewModel
    var onAddExpense: () -> Void
    var onAddIncome: () -> Void

    var body: some View {
        ScrollView {
            FinanceOverviewContent(
                viewModel: viewModel,
                onAddExpense: onAddExpense,
                onAddIncome: onAddIncome
            )
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

// MARK: - Budget Status

struct BudgetStatusInfo {
    enum Status {
        case ok, warning, over, noBudgets

        var color: Color {
            switch self {
            case .ok: return .nexusSuccess
            case .warning: return .nexusWarning
            case .over: return .nexusError
            case .noBudgets: return .gray
            }
        }
    }

    let status: Status
    let message: String
}

#Preview {
    FinanceView(viewModel: FinanceViewModel())
}
