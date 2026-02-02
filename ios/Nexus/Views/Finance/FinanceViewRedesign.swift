import SwiftUI

// MARK: - Finance View Redesign
// Single dashboard with hierarchy: Today → Month → Recent
// Max 8 cards, premium calm design

struct FinanceViewRedesign: View {
    @StateObject private var viewModel = FinanceViewModel()
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingSettings = false
    @State private var showingAllTransactions = false

    private var coordinator: SyncCoordinator { SyncCoordinator.shared }

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
                    if !viewModel.summary.categoryBreakdown.isEmpty {
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
                    if let insight = viewModel.serverInsights.first {
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
                viewModel.loadFinanceSummary()
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
                        Task { await viewModel.triggerSMSImport() }
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
            .sheet(isPresented: $showingAllTransactions) {
                AllTransactionsSheet()
            }
        }
    }

    // MARK: - Convenience

    private var currency: String {
        viewModel.summary.currency
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
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatCurrency(viewModel.summary.totalSpent, currency: currency))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.recentTransactions.count) transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                        Text(formatCurrency(viewModel.summary.totalSpent, currency: currency))
                            .font(.title2.weight(.bold))
                    }

                    Spacer()

                    let totalBudget = viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
                    if totalBudget > 0 {
                        let budgetPercent = (viewModel.summary.totalSpent / totalBudget) * 100
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
                            Text("of \(formatCurrencyShort(totalBudget))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        let dubaiCal = Constants.Dubai.calendar
                        let daysRemaining = dubaiCal.range(of: .day, in: .month, for: Date())!.count -
                                           dubaiCal.component(.day, from: Date())
                        VStack(spacing: 2) {
                            Text("\(daysRemaining)")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.nexusFinance)
                            Text("days left")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
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

                let sorted = viewModel.summary.categoryBreakdown
                    .sorted { $0.value > $1.value }
                    .prefix(3)

                ForEach(Array(sorted), id: \.key) { key, value in
                    let total = viewModel.summary.totalSpent
                    CategoryRowView(
                        name: key.capitalized,
                        icon: categoryIcon(for: key),
                        amount: abs(value),
                        progress: total > 0 ? abs(value) / total : 0,
                        currency: currency
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

                ForEach(viewModel.recentTransactions.prefix(5)) { tx in
                    RecentTransactionRow(transaction: tx, currency: currency)

                    if tx.id != viewModel.recentTransactions.prefix(5).last?.id {
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Income")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatCurrencyShort(viewModel.summary.totalIncome))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Expenses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatCurrencyShort(viewModel.summary.totalSpent))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    let net = viewModel.summary.totalIncome - viewModel.summary.totalSpent
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((net >= 0 ? "+" : "") + formatCurrencyShort(net))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(net >= 0 ? .green : .red)
                }

                Spacer()
            }
        }
    }

    // MARK: - 7. Insight

    private func insightCard(_ insight: RankedInsight) -> some View {
        SimpleCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.nexusFinance)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.medium))
                    Text(insight.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
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

    // MARK: - Helpers

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "grocery", "groceries": return "cart.fill"
        case "restaurant", "food", "dining": return "fork.knife"
        case "transport", "transportation": return "car.fill"
        case "utilities": return "house.fill"
        case "entertainment": return "tv.fill"
        case "health", "medical": return "heart.fill"
        case "shopping": return "bag.fill"
        default: return "creditcard.fill"
        }
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
    let transaction: Transaction
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: categoryIcon)
                    .font(.system(size: 14))
                    .foregroundColor(categoryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchantName)
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
                    Text(transaction.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(formatCurrency(transaction.amount, currency: currency))
                .font(.subheadline.weight(.medium))
                .foregroundColor(transaction.amount < 0 ? .primary : .green)
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
