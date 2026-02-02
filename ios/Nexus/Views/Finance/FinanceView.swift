import SwiftUI
import Combine

struct FinanceView: View {
    @StateObject private var viewModel = FinanceViewModel()
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

                    FinancePlanView(viewModel: viewModel)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.triggerSMSImport()
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.nexusFinance)
                        }
                    }
                    .disabled(viewModel.isLoading)
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

    private var mtdSpend: Double {
        viewModel.summary.totalSpent
    }

    private var mtdIncome: Double {
        viewModel.summary.totalIncome
    }

    private var topCategories: [(String, Double)] {
        Array(viewModel.summary.categoryBreakdown
            .sorted { $0.value > $1.value }
            .prefix(3))
            .map { ($0.key, $0.value) }
    }

    private var budgetStatus: BudgetStatusInfo {
        let budgets = viewModel.summary.budgets
        guard !budgets.isEmpty else {
            return BudgetStatusInfo(status: .noBudgets, message: "No budgets set")
        }

        let totalBudget = budgets.reduce(0) { $0 + $1.budgetAmount }
        let totalSpent = budgets.reduce(0) { $0 + ($1.spent ?? 0) }
        let percentage = totalBudget > 0 ? (totalSpent / totalBudget) * 100 : 0

        if percentage > 100 {
            return BudgetStatusInfo(status: .over, message: String(format: "%.0f%% of budget", percentage))
        } else if percentage > 80 {
            return BudgetStatusInfo(status: .warning, message: String(format: "%.0f%% of budget", percentage))
        } else {
            return BudgetStatusInfo(status: .ok, message: String(format: "%.0f%% of budget", percentage))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Freshness indicator
                if let lastUpdated = viewModel.lastUpdated {
                    financeFreshnessIndicator(lastUpdated: lastUpdated, isOffline: viewModel.isOffline)
                }

                // MTD Spend Card with Budget Status
                mtdSpendCard

                // Top Categories
                if !topCategories.isEmpty {
                    topCategoriesCard
                }

                // Cashflow Mini
                cashflowCard

                // Monthly Obligations
                if viewModel.monthlyObligations > 0 {
                    obligationsSummary
                }

                // Upcoming Bills
                if !viewModel.upcomingBills.isEmpty {
                    upcomingBillsCard
                }

                // Action Row
                actionRow

                // Insights Card (max 2)
                insightsCard

                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            viewModel.loadFinanceSummary()
        }
    }

    // MARK: - MTD Spend Card

    private var mtdSpendCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Month to Date")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(mtdSpend, currency: AppSettings.shared.defaultCurrency))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.primary)
                }
                Spacer()
                budgetStatusBadge
            }

            // Progress to budget
            if case .ok = budgetStatus.status, !viewModel.summary.budgets.isEmpty {
                let totalBudget = viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
                let progress = totalBudget > 0 ? min(mtdSpend / totalBudget, 1.0) : 0

                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(Color.nexusFinance)
                                .frame(width: geo.size.width * progress, height: 6)
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 6)

                    Text(formatCurrency(totalBudget - mtdSpend, currency: AppSettings.shared.defaultCurrency) + " remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var budgetStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(budgetStatus.status.color)
                .frame(width: 8, height: 8)
            Text(budgetStatus.message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(budgetStatus.status.color.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Top Categories Card

    private var topCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Categories")
                .font(.headline)

            ForEach(topCategories, id: \.0) { category, amount in
                HStack {
                    Text(category.capitalized)
                        .font(.subheadline)

                    Spacer()

                    Text(formatCurrency(amount, currency: AppSettings.shared.defaultCurrency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Mini progress bar
                GeometryReader { geo in
                    let maxAmount = topCategories.first?.1 ?? 1
                    let progress = maxAmount > 0 ? amount / maxAmount : 0

                    Rectangle()
                        .fill(Color.nexusFinance.opacity(0.3))
                        .frame(width: geo.size.width * progress, height: 4)
                        .cornerRadius(2)
                }
                .frame(height: 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Cashflow Card

    private var cashflowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cashflow This Month")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("Income")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatCurrency(mtdIncome, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Spend")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.red)
                    }
                    Text(formatCurrency(mtdSpend, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }

            // Net
            let net = mtdIncome - mtdSpend
            Divider()
            HStack {
                Text("Net")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text((net >= 0 ? "+" : "") + formatCurrency(net, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(net >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Monthly Obligations Summary

    private var obligationsSummary: some View {
        HStack {
            Image(systemName: "repeat.circle.fill")
                .foregroundColor(.orange)
            Text("Monthly obligations")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatCurrency(viewModel.monthlyObligations, currency: AppSettings.shared.defaultCurrency))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Upcoming Bills Card

    private var upcomingBillsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Upcoming Bills")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.upcomingBills.prefix(5).count) of \(viewModel.upcomingBills.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(viewModel.upcomingBills.prefix(5))) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline)
                        if let date = item.dueDateFormatted {
                            Text(date)
                                .font(.caption)
                                .foregroundColor(item.isOverdue ? .red : item.isDueSoon ? .orange : .secondary)
                        }
                    }
                    Spacer()
                    Text(formatCurrency(item.amount, currency: item.currency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onAddExpense) {
                VStack(spacing: 6) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                    Text("Expense")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }

            Button(action: onAddIncome) {
                VStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Income")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Insights Card

    private var insightsCard: some View {
        let insights = generateInsights()

        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Insights")
                            .font(.headline)
                    }

                    ForEach(insights.prefix(2), id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(insight)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            }
        }
    }

    private func generateInsights() -> [String] {
        // Prefer server-ranked insights for finance
        let server = viewModel.serverInsights
        if !server.isEmpty {
            return server.prefix(2).map { $0.description }
        }

        // Fallback: client-side insights when server returns none
        var insights: [String] = []

        let overBudget = viewModel.summary.budgets.filter { ($0.spent ?? 0) > $0.budgetAmount }
        if !overBudget.isEmpty {
            let categories = overBudget.map { $0.category.capitalized }.joined(separator: ", ")
            insights.append("You're over budget on: \(categories)")
        }

        let net = mtdIncome - mtdSpend
        if net < 0 {
            insights.append("You've spent \(formatCurrency(abs(net), currency: AppSettings.shared.defaultCurrency)) more than you've earned this month.")
        }

        return insights
    }

    private func financeFreshnessIndicator(lastUpdated: Date, isOffline: Bool) -> some View {
        HStack(spacing: 6) {
            if let freshness = viewModel.financeFreshness {
                Circle()
                    .fill(freshness.isStale ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(freshness.syncTimeLabel)
                    .font(.caption)
                    .foregroundColor(freshness.isStale ? .orange : .secondary)
            } else {
                Circle()
                    .fill(isOffline ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isOffline {
                Text("(Offline)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Budget Status

struct BudgetStatusInfo {
    enum Status {
        case ok, warning, over, noBudgets

        var color: Color {
            switch self {
            case .ok: return .green
            case .warning: return .orange
            case .over: return .red
            case .noBudgets: return .gray
            }
        }
    }

    let status: Status
    let message: String
}

#Preview {
    FinanceView()
}
