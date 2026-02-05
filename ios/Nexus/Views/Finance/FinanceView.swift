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
                // Freshness indicator - only show if stale (>5 min) or offline
                if let lastUpdated = viewModel.lastUpdated,
                   Date().timeIntervalSince(lastUpdated) > 300 || viewModel.isOffline {
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

                // Recent Transactions
                if !viewModel.recentTransactions.isEmpty {
                    recentTransactionsCard
                }

                // Monthly Obligations
                if viewModel.monthlyObligations > 0 {
                    obligationsSummary
                }

                // Debt Summary
                if !viewModel.activeDebts.isEmpty {
                    debtSummaryCard
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
                        .foregroundColor(.nexusError)
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
            viewModel.loadDebts()
        }
    }

    // MARK: - MTD Spend Card

    private var mtdSpendCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Month to Date Spending")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text(formatCurrency(mtdSpend, currency: AppSettings.shared.defaultCurrency))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                budgetStatusBadge
            }

            // Progress to budget
            if case .ok = budgetStatus.status, !viewModel.summary.budgets.isEmpty {
                let totalBudget = viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
                let progress = totalBudget > 0 ? min(mtdSpend / totalBudget, 1.0) : 0

                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 8)
                                .cornerRadius(4)

                            Rectangle()
                                .fill(Color.nexusFinance)
                                .frame(width: geo.size.width * progress, height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text(formatCurrency(totalBudget - mtdSpend, currency: AppSettings.shared.defaultCurrency))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("remaining of \(formatCurrency(totalBudget, currency: AppSettings.shared.defaultCurrency))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    private var budgetStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(budgetStatus.status.color)
                .frame(width: 8, height: 8)
            
            Text(budgetStatus.message)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(budgetStatus.status.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(budgetStatus.status.color.opacity(0.12))
        .cornerRadius(14)
    }

    // MARK: - Top Categories Card

    private var topCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Categories This Month")
                .font(.headline)
                .fontWeight(.semibold)

            ForEach(topCategories, id: \.0) { category, amount in
                VStack(spacing: 8) {
                    HStack {
                        Text(category.capitalized)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(formatCurrency(amount, currency: AppSettings.shared.defaultCurrency))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    // Mini progress bar
                    GeometryReader { geo in
                        let maxAmount = topCategories.first?.1 ?? 1
                        let progress = maxAmount > 0 ? amount / maxAmount : 0

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 6)
                                .cornerRadius(3)
                            
                            Rectangle()
                                .fill(Color.nexusFinance.opacity(0.8))
                                .frame(width: geo.size.width * progress, height: 6)
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 6)
                }
                
                if category != topCategories.last?.0 {
                    Divider()
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Cashflow Card

    private var cashflowCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cashflow This Month")
                .font(.headline)
                .fontWeight(.semibold)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.nexusSuccess)
                            .font(.subheadline)
                        Text("Income")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }

                    Text(formatCurrency(mtdIncome, currency: AppSettings.shared.defaultCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.nexusSuccess)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Spending")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.nexusError)
                            .font(.subheadline)
                    }

                    Text(formatCurrency(mtdSpend, currency: AppSettings.shared.defaultCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.nexusError)
                }
            }

            // Net cashflow
            let net = mtdIncome - mtdSpend
            
            Divider()
            
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: net >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(net >= 0 ? .nexusSuccess : .nexusWarning)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Cashflow")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text((net >= 0 ? "+" : "") + formatCurrency(net, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(net >= 0 ? .nexusSuccess : .nexusWarning)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Debt Summary Card

    private var debtSummaryCard: some View {
        NavigationLink(destination: DebtsListView(viewModel: viewModel)) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.nexusMood)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debts")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("\(viewModel.activeDebts.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(formatCurrency(viewModel.totalDebtRemaining, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.nexusMood)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Obligations Summary

    private var obligationsSummary: some View {
        HStack {
            Image(systemName: "repeat.circle.fill")
                .foregroundColor(.nexusWarning)
            Text("Monthly obligations")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatCurrency(viewModel.monthlyObligations, currency: AppSettings.shared.defaultCurrency))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.nexusWarning)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }

    // MARK: - Upcoming Bills Card

    private var upcomingBillsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Bills")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if viewModel.upcomingBills.count > 5 {
                    Text("Showing 5 of \(viewModel.upcomingBills.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(Array(viewModel.upcomingBills.prefix(5))) { item in
                HStack(spacing: 12) {
                    // Urgency indicator
                    Circle()
                        .fill(item.isOverdue ? Color.nexusError : item.isDueSoon ? Color.nexusWarning : Color.nexusPrimary)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let date = item.dueDateFormatted {
                            Text(date)
                                .font(.caption)
                                .foregroundColor(item.isOverdue ? .nexusError : item.isDueSoon ? .nexusWarning : .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatCurrency(item.amount, currency: item.currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
                
                if item.id != viewModel.upcomingBills.prefix(5).last?.id {
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
        .padding(16)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Recent Transactions

    private var recentTransactionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(viewModel.recentTransactions.prefix(5).count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(viewModel.recentTransactions.prefix(5)) { tx in
                TransactionRow(transaction: tx)
                
                if tx.id != viewModel.recentTransactions.prefix(5).last?.id {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .padding(16)
        .background(Color.nexusCardBackground)
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
                .background(Color.nexusError.opacity(0.1))
                .foregroundColor(.nexusError)
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
                .background(Color.nexusSuccess.opacity(0.1))
                .foregroundColor(.nexusSuccess)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Insights Card

    private var insightsCard: some View {
        let insights = generateInsights()

        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.nexusFood)
                            .font(.title3)
                        Text("Financial Insights")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    ForEach(insights.prefix(2), id: \.self) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                            
                            Text(insight)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .background(Color.nexusFood.opacity(0.08))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.nexusFood.opacity(0.2), lineWidth: 1)
                )
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
        HStack(spacing: 8) {
            if let freshness = viewModel.financeFreshness {
                // Use server-provided freshness data when available
                Circle()
                    .fill(freshness.isStale ? Color.nexusWarning : Color.nexusSuccess)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(freshness.isStale ? "Data may be outdated" : "Data is current")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(freshness.isStale ? .nexusWarning : .secondary)
                    
                    Text(freshness.syncTimeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                // Fallback to client-side staleness detection
                let age = Date().timeIntervalSince(lastUpdated)
                let isStale = age > 300 // 5 minutes
                
                Circle()
                    .fill(isOffline ? Color.nexusWarning : isStale ? Color.nexusFood : Color.nexusSuccess)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    if isOffline {
                        Text("Offline — showing cached data")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.nexusWarning)
                    } else if isStale {
                        Text("Last updated \(lastUpdated, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Synced recently")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Pull to refresh")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
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
