import SwiftUI

// MARK: - Finance View Redesign
// Single dashboard with hierarchy: Today → Month → Recent
// Max 8 cards, premium calm design

struct FinanceViewRedesign: View {
    @StateObject private var viewModel = FinanceDashboardViewModel()
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingSettings = false
    @State private var showingAllTransactions = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Freshness Badge
                    FreshnessBadge(
                        lastUpdated: viewModel.lastUpdated,
                        isOffline: viewModel.isOffline
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    // 1. Today Spend (Hero Card)
                    todaySpendCard

                    // 2. Month Progress
                    monthProgressCard

                    // 3. Categories
                    if !viewModel.topCategories.isEmpty {
                        categoriesCard
                    }

                    // 4. Quick Actions
                    quickActionsRow

                    // 5. Recent Transactions
                    if !viewModel.recentTransactions.isEmpty {
                        recentTransactionsCard
                    }

                    // 6. Cashflow Summary
                    cashflowCard

                    // 7. Insight (if available)
                    if let insight = viewModel.insight {
                        insightCard(insight)
                    }

                    // Error message
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .refreshable {
                await viewModel.refresh()
            }
            .onAppear {
                viewModel.loadDashboard()
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
                        Task { await viewModel.triggerImport() }
                    }) {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.nexusFinance)
                        }
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
            .sheet(isPresented: $showingSettings) {
                FinancePlanningView()
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: FinanceViewModel())
            }
            .sheet(isPresented: $showingAddIncome) {
                IncomeView(viewModel: FinanceViewModel())
            }
            .sheet(isPresented: $showingAllTransactions) {
                AllTransactionsSheet()
            }
        }
    }

    // MARK: - 1. Today Spend (Hero)

    private var todaySpendCard: some View {
        HeroCard(accentColor: .nexusFinance) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.isTodayUnusual {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text("High")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCurrency(viewModel.todaySpend, currency: viewModel.currency))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                HStack(spacing: 16) {
                    // Transaction count
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.todayTransactionCount) transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // vs Yesterday delta
                    if let delta = viewModel.todayVsYesterday {
                        DeltaBadge(delta, suffix: "% vs yesterday", invertColors: true)
                    }
                }
            }
        }
    }

    // MARK: - 2. Month Progress

    private var monthProgressCard: some View {
        SimpleCard {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Month")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text(formatCurrency(viewModel.monthSpend, currency: viewModel.currency))
                            .font(.title2.weight(.bold))
                    }

                    Spacer()

                    // Budget ring or days remaining
                    if let budgetPercent = viewModel.monthBudgetUsedPercent,
                       let budget = viewModel.monthBudget {
                        VStack(spacing: 4) {
                            ZStack {
                                ProgressRing(
                                    progress: min(budgetPercent / 100, 1.0),
                                    color: budgetPercent > 90 ? .orange : .nexusFinance,
                                    lineWidth: 6,
                                    size: 50
                                )
                                Text("\(Int(budgetPercent))%")
                                    .font(.caption.weight(.bold))
                            }
                            Text("of \(formatCurrencyShort(budget))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(spacing: 2) {
                            Text("\(viewModel.daysRemaining)")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.nexusFinance)
                            Text("days left")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Budget remaining text
                if let remaining = viewModel.monthBudgetRemaining {
                    HStack {
                        Image(systemName: remaining >= 0 ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(remaining >= 0 ? .green : .orange)
                        Text(remaining >= 0 ?
                             "\(formatCurrency(remaining, currency: viewModel.currency)) remaining" :
                             "\(formatCurrency(abs(remaining), currency: viewModel.currency)) over budget")
                            .font(.caption)
                            .foregroundColor(remaining >= 0 ? .secondary : .orange)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - 3. Categories

    private var categoriesCard: some View {
        SimpleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Categories")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                ForEach(viewModel.topCategories) { category in
                    CategoryRowView(
                        name: category.name,
                        icon: category.icon ?? "creditcard.fill",
                        amount: category.spent,
                        progress: category.percentOfTotal / 100,
                        currency: viewModel.currency
                    )
                }
            }
        }
    }

    // MARK: - 4. Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            FinanceQuickAction(
                title: "Expense",
                icon: "minus.circle.fill",
                color: .red
            ) {
                showingAddExpense = true
            }

            FinanceQuickAction(
                title: "Income",
                icon: "plus.circle.fill",
                color: .green
            ) {
                showingAddIncome = true
            }

            FinanceQuickAction(
                title: "Receipt",
                icon: "doc.text.viewfinder",
                color: .nexusFinance
            ) {
                // TODO: Receipt scanning
            }
        }
    }

    // MARK: - 5. Recent Transactions

    private var recentTransactionsCard: some View {
        SimpleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { showingAllTransactions = true }) {
                        HStack(spacing: 4) {
                            Text("See all")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(.nexusFinance)
                    }
                }

                ForEach(viewModel.recentTransactions) { tx in
                    RecentTransactionRow(transaction: tx, currency: viewModel.currency)

                    if tx.id != viewModel.recentTransactions.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - 6. Cashflow

    private var cashflowCard: some View {
        SimpleCard(padding: 12) {
            HStack(spacing: 16) {
                // Income
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Income")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatCurrencyShort(viewModel.monthIncome))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }

                Divider()
                    .frame(height: 30)

                // Expenses
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Expenses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatCurrencyShort(viewModel.monthSpend))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                }

                Divider()
                    .frame(height: 30)

                // Net
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((viewModel.monthNet >= 0 ? "+" : "") + formatCurrencyShort(viewModel.monthNet))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(viewModel.monthNet >= 0 ? .green : .red)
                }

                Spacer()
            }
        }
    }

    // MARK: - 7. Insight

    private func insightCard(_ insight: FinanceInsightDTO) -> some View {
        SimpleCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundColor(insightColor(insight.severity))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.subheadline.weight(.medium))
                    Text(insight.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    private func insightColor(_ severity: FinanceInsightDTO.InsightSeverity) -> Color {
        switch severity {
        case .info: return .nexusFinance
        case .warning: return .orange
        case .alert: return .red
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Components

private struct CategoryRowView: View {
    let name: String
    let icon: String
    let amount: Double
    let progress: Double
    let currency: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.nexusFinance)
                    .frame(width: 20)

                Text(name)
                    .font(.subheadline)

                Spacer()

                Text(formatCurrency(amount, currency: currency))
                    .font(.subheadline.weight(.medium))
            }

            HorizontalProgressBar(
                progress: progress,
                color: .nexusFinance.opacity(0.7),
                height: 4
            )
        }
    }
}

private struct FinanceQuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

private struct RecentTransactionRow: View {
    let transaction: FinanceTransactionDTO
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: categoryIcon)
                    .font(.system(size: 14))
                    .foregroundColor(categoryColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let category = transaction.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(transaction.time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Amount
            Text(formatCurrency(transaction.amount, currency: currency))
                .font(.subheadline.weight(.medium))
                .foregroundColor(transaction.isExpense ? .primary : .green)
        }
    }

    private var categoryIcon: String {
        guard let category = transaction.category else { return "creditcard" }
        switch category.lowercased() {
        case "grocery", "groceries": return "cart.fill"
        case "restaurant", "food": return "fork.knife"
        case "transport": return "car.fill"
        case "utilities": return "house.fill"
        default: return "creditcard"
        }
    }

    private var categoryColor: Color {
        guard let category = transaction.category else { return .gray }
        switch category.lowercased() {
        case "grocery", "groceries": return .green
        case "restaurant", "food": return .orange
        case "transport": return .blue
        case "utilities": return .purple
        default: return .nexusFinance
        }
    }
}

// MARK: - All Transactions Sheet

private struct AllTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FinanceViewModel()

    var body: some View {
        NavigationView {
            FinanceActivityView(viewModel: viewModel)
                .navigationTitle("All Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Currency Formatting Helpers

private func formatCurrencyShort(_ amount: Double) -> String {
    let absAmount = abs(amount)
    if absAmount >= 1000 {
        return String(format: "%.1fK", absAmount / 1000)
    }
    return String(format: "%.0f", absAmount)
}

// MARK: - Preview

#Preview {
    FinanceViewRedesign()
}
