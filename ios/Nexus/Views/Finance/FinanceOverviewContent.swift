import SwiftUI
import Combine
import Charts

struct FinanceOverviewContent: View {
    @ObservedObject var viewModel: FinanceViewModel
    var onAddExpense: () -> Void
    var onAddIncome: () -> Void

    // MARK: - Month Navigation State
    @State private var selectedMonth: Date = Date()
    @State private var monthlyTrends: [MonthlySpending] = []
    @State private var isLoadingTrends = false

    // MARK: - Dynamic Type Scaling
    @ScaledMetric(relativeTo: .title) private var mtdSpendTextSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var cashflowTextSize: CGFloat = 20

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var selectedMonthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private var mtdSpend: Double {
        if !isCurrentMonth, let monthSpend = monthSpend {
            return monthSpend
        }
        return viewModel.summary.totalSpent
    }

    private var mtdIncome: Double {
        if !isCurrentMonth, let monthIncome = monthIncome {
            return monthIncome
        }
        return viewModel.summary.totalIncome
    }

    @State private var monthSpend: Double?
    @State private var monthIncome: Double?

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

    private var hasNoData: Bool {
        viewModel.summary.totalSpent == 0 &&
        viewModel.summary.totalIncome == 0 &&
        viewModel.recentTransactions.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            // Show error state when there's an error and no meaningful data
            if let error = viewModel.errorMessage, hasNoData {
                ErrorStateView(
                    message: error,
                    onRetry: { viewModel.loadFinanceSummary() }
                )
            } else {
                if let lastUpdated = viewModel.lastUpdated,
                   Date().timeIntervalSince(lastUpdated) > 300 || viewModel.isOffline {
                    financeFreshnessIndicator(lastUpdated: lastUpdated, isOffline: viewModel.isOffline)
                }

                // MARK: - Month Navigation
                monthNavigationHeader

                // MARK: - Spending Trend Mini-Chart
                if !monthlyTrends.isEmpty {
                    spendingTrendMiniChart
                }

                // MARK: - Summary Section
                VStack(spacing: 16) {
                    mtdSpendCard
                    cashflowCard
                }

                // MARK: - Financial Position Card
                NavigationLink(destination: FinancialPositionView()) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Financial Position")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Accounts, balances & upcoming bills")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "building.columns.fill")
                            .font(.title3)
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                    }
                    .padding(NexusTheme.Spacing.lg)
                    .background(NexusTheme.Colors.card)
                    .cornerRadius(NexusTheme.Radius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                            .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                    )
                }

                // MARK: - Cashflow Projection Card
                NavigationLink(destination: CashflowProjectionView(viewModel: viewModel)) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("30-Day Projection")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("See upcoming income and expenses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title3)
                            .foregroundColor(NexusTheme.Colors.accent)
                    }
                    .padding(NexusTheme.Spacing.lg)
                    .background(NexusTheme.Colors.card)
                    .cornerRadius(NexusTheme.Radius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                            .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                    )
                }

                // MARK: - Category Pie Chart
                if !viewModel.summary.categoryBreakdown.isEmpty && mtdSpend > 0 {
                    categoryPieChart
                }

                // MARK: - Budget Progress Per Category
                if !viewModel.summary.budgets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("BUDGET STATUS")
                        budgetProgressCards
                    }
                }

                // MARK: - Spending Breakdown Section
                if !topCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("SPENDING BREAKDOWN")
                        topCategoriesCard
                    }
                }

                // MARK: - Transactions Section
                if !viewModel.recentTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("RECENT ACTIVITY")
                        recentTransactionsCard
                    }
                }

                // MARK: - Upcoming Section
                if viewModel.monthlyObligations > 0 || !viewModel.upcomingBills.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("UPCOMING")
                        if viewModel.monthlyObligations > 0 {
                            obligationsSummary
                        }
                        if !viewModel.upcomingBills.isEmpty {
                            upcomingBillsCard
                        }
                    }
                }

                // MARK: - Quick Actions
                actionRow

                // MARK: - Insights Section
                if !generateInsights().isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("INSIGHTS")
                        insightsCard
                    }
                }
            }
        }
        .padding()
        .onAppear {
            viewModel.loadFinanceSummary()
            loadMonthlyTrends()
        }
        .onChange(of: selectedMonth) {
            loadMonthData()
        }
    }

    // MARK: - Month Navigation Header

    private var monthNavigationHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(NexusTheme.Colors.accent)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(selectedMonthLabel)
                    .font(.headline)
                    .fontWeight(.semibold)

                if !isCurrentMonth {
                    Button("Back to current") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMonth = Date()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.accent)
                }
            }

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(isCurrentMonth ? .secondary.opacity(0.3) : NexusTheme.Colors.accent)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        }
    }

    private func nextMonth() {
        guard !isCurrentMonth else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        }
    }

    // MARK: - Spending Trend Mini-Chart

    @ViewBuilder
    private var spendingTrendMiniChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending Trend")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                NavigationLink(destination: MonthlyTrendsView(viewModel: viewModel)) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(NexusTheme.Colors.accent)
                }
            }

            if isLoadingTrends {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 80)
            } else if #available(iOS 16.0, *) {
                Chart(monthlyTrends.suffix(6)) { item in
                    BarMark(
                        x: .value("Month", item.monthName),
                        y: .value("Amount", item.totalSpent)
                    )
                    .foregroundStyle(
                        item.monthName == currentMonthName
                            ? NexusTheme.Colors.accent
                            : NexusTheme.Colors.accent.opacity(0.4)
                    )
                    .cornerRadius(4)
                }
                .frame(height: 80)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                // iOS 15 fallback - simple bar visualization
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(monthlyTrends.suffix(6)) { item in
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(item.monthName == currentMonthName
                                    ? NexusTheme.Colors.accent
                                    : NexusTheme.Colors.accent.opacity(0.4))
                                .frame(height: barHeight(for: item.totalSpent))
                                .cornerRadius(2)

                            Text(item.monthName)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: Date())
    }

    private func barHeight(for amount: Double) -> CGFloat {
        guard let maxAmount = monthlyTrends.suffix(6).map({ $0.totalSpent }).max(), maxAmount > 0 else {
            return 20
        }
        let ratio = amount / maxAmount
        return max(8, CGFloat(ratio) * 60)
    }

    private func loadMonthData() {
        if isCurrentMonth {
            // Current month: use the summary endpoint (live MTD data)
            monthSpend = nil
            monthIncome = nil
            viewModel.loadFinanceSummary()
            loadMonthlyTrends()
        } else {
            // Past month: load from transactions endpoint with date filter
            let cal = Calendar.current
            guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)),
                  let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth) else { return }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let startStr = fmt.string(from: startOfMonth)
            let endStr = fmt.string(from: startOfNextMonth)

            Task {
                await viewModel.loadMonthTransactions(startDate: startStr, endDate: endStr)
                monthSpend = viewModel.summary.totalSpent
                monthIncome = viewModel.summary.totalIncome
            }
        }
    }

    private func loadMonthlyTrends() {
        isLoadingTrends = true
        Task {
            do {
                let response = try await NexusAPI.shared.fetchMonthlyTrends(months: 6)
                if response.success, let data = response.data {
                    await MainActor.run {
                        monthlyTrends = data.monthlySpending
                        isLoadingTrends = false
                    }
                } else {
                    await MainActor.run {
                        isLoadingTrends = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingTrends = false
                }
            }
        }
    }

    // MARK: - Category Pie Chart

    @ViewBuilder
    private var categoryPieChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending Distribution")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                NavigationLink(destination: SpendingChartsView(
                    categoryBreakdown: viewModel.summary.categoryBreakdown,
                    totalSpent: mtdSpend
                )) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(NexusTheme.Colors.accent)
                }
            }

            if #available(iOS 16.0, *) {
                let sortedCategories = viewModel.summary.categoryBreakdown
                    .map { ($0.key, $0.value) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(5)

                Chart(Array(sortedCategories), id: \.0) { item in
                    SectorMark(
                        angle: .value("Amount", abs(item.1)),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", item.0.capitalized))
                }
                .frame(height: 150)
                .chartLegend(position: .trailing, alignment: .center, spacing: 8)
            } else {
                // iOS 15 fallback - horizontal bars
                let sortedCategories = viewModel.summary.categoryBreakdown
                    .map { ($0.key, $0.value) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(5)

                VStack(spacing: 8) {
                    ForEach(Array(sortedCategories), id: \.0) { category, amount in
                        HStack {
                            Text(category.capitalized)
                                .font(.caption)
                                .frame(width: 80, alignment: .leading)

                            GeometryReader { geo in
                                let percentage = mtdSpend > 0 ? abs(amount) / mtdSpend : 0
                                Rectangle()
                                    .fill(NexusTheme.Colors.accent.opacity(0.8))
                                    .frame(width: geo.size.width * percentage)
                                    .cornerRadius(2)
                            }
                            .frame(height: 8)

                            Text(String(format: "%.0f%%", (abs(amount) / mtdSpend) * 100))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Budget Progress Cards

    private var budgetProgressCards: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.summary.budgets.sorted {
                let pct1 = ($0.spent ?? 0) / max($0.budgetAmount, 1)
                let pct2 = ($1.spent ?? 0) / max($1.budgetAmount, 1)
                return pct1 > pct2
            }.prefix(4)) { budget in
                budgetProgressRow(budget)
            }

            if viewModel.summary.budgets.count > 4 {
                NavigationLink(destination: FinanceBudgetsView(viewModel: viewModel)) {
                    HStack {
                        Text("View all \(viewModel.summary.budgets.count) budgets")
                            .font(.subheadline)
                            .foregroundColor(NexusTheme.Colors.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(NexusTheme.Colors.cardAlt)
                    .cornerRadius(NexusTheme.Radius.sm)
                }
            }
        }
    }

    private func budgetProgressRow(_ budget: Budget) -> some View {
        let spent = budget.spent ?? 0
        let limit = budget.budgetAmount
        let percentage = limit > 0 ? spent / limit : 0
        let isOver = percentage > 1.0
        let isWarning = percentage > 0.8 && !isOver

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(budget.category.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 4) {
                    Text(formatCurrency(spent, currency: AppSettings.shared.defaultCurrency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isOver ? NexusTheme.Colors.Semantic.red : isWarning ? NexusTheme.Colors.Semantic.amber : .primary)

                    Text("/ \(formatCurrency(limit, currency: AppSettings.shared.defaultCurrency))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(NexusTheme.Colors.divider)
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(isOver ? NexusTheme.Colors.Semantic.red : isWarning ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                        .frame(width: geo.size.width * min(percentage, 1.0), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.sm)
                .stroke(isOver ? NexusTheme.Colors.Semantic.red.opacity(0.3) : NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.leading, 4)
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
                        .font(.system(size: mtdSpendTextSize, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                Spacer()

                budgetStatusBadge
            }

            if case .ok = budgetStatus.status, !viewModel.summary.budgets.isEmpty {
                let totalBudget = viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
                let progress = totalBudget > 0 ? min(mtdSpend / totalBudget, 1.0) : 0

                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(NexusTheme.Colors.divider)
                                .frame(height: 8)
                                .cornerRadius(4)

                            Rectangle()
                                .fill(NexusTheme.Colors.Semantic.green)
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
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
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

                    GeometryReader { geo in
                        let maxAmount = topCategories.first?.1 ?? 1
                        let progress = maxAmount > 0 ? amount / maxAmount : 0

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(NexusTheme.Colors.divider)
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(NexusTheme.Colors.Semantic.green.opacity(0.8))
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
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
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
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                            .font(.subheadline)
                        Text("Income")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }

                    Text(formatCurrency(mtdIncome, currency: AppSettings.shared.defaultCurrency))
                        .font(.system(size: cashflowTextSize, weight: .bold, design: .rounded))
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Spending")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(NexusTheme.Colors.Semantic.red)
                            .font(.subheadline)
                    }

                    Text(formatCurrency(mtdSpend, currency: AppSettings.shared.defaultCurrency))
                        .font(.system(size: cashflowTextSize, weight: .bold, design: .rounded))
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                }
            }

            let net = mtdIncome - mtdSpend

            Divider()

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: net >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(net >= 0 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Cashflow")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text((net >= 0 ? "+" : "") + formatCurrency(net, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(net >= 0 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(NexusTheme.Colors.card)
        .cornerRadius(16)
    }

    // MARK: - Monthly Obligations Summary

    private var obligationsSummary: some View {
        HStack {
            Image(systemName: "repeat.circle.fill")
                .foregroundColor(NexusTheme.Colors.Semantic.amber)
            Text("Monthly obligations")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatCurrency(viewModel.monthlyObligations, currency: AppSettings.shared.defaultCurrency))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(NexusTheme.Colors.Semantic.amber)
        }
        .padding()
        .background(NexusTheme.Colors.card)
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
                    Circle()
                        .fill(item.isOverdue ? NexusTheme.Colors.Semantic.red : item.isDueSoon ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.accent)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let date = item.dueDateFormatted {
                            Text(date)
                                .font(.caption)
                                .foregroundColor(item.isOverdue ? NexusTheme.Colors.Semantic.red : item.isDueSoon ? NexusTheme.Colors.Semantic.amber : .secondary)
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
        .background(NexusTheme.Colors.card)
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
        .background(NexusTheme.Colors.card)
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
                .background(NexusTheme.Colors.Semantic.red.opacity(0.1))
                .foregroundColor(NexusTheme.Colors.Semantic.red)
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
                .background(NexusTheme.Colors.Semantic.green.opacity(0.1))
                .foregroundColor(NexusTheme.Colors.Semantic.green)
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
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
                .background(NexusTheme.Colors.Semantic.amber.opacity(0.08))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NexusTheme.Colors.Semantic.amber.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    private func generateInsights() -> [String] {
        let server = viewModel.serverInsights
        if !server.isEmpty {
            return server.prefix(2).map { $0.description }
        }

        var insights: [String] = []

        let overBudget = viewModel.summary.budgets.filter { ($0.spent ?? 0) > $0.budgetAmount }
        if !overBudget.isEmpty {
            let categories = Array(Set(overBudget.map { $0.category.capitalized })).sorted().joined(separator: ", ")
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
                Circle()
                    .fill(freshness.isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(freshness.isStale ? "Data may be outdated" : "Data is current")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(freshness.isStale ? NexusTheme.Colors.Semantic.amber : .secondary)

                    Text(freshness.syncTimeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                let age = Date().timeIntervalSince(lastUpdated)
                let isStale = age > 300

                Circle()
                    .fill(isOffline ? NexusTheme.Colors.Semantic.amber : isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    if isOffline {
                        Text("Offline — showing cached data")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
        .background(NexusTheme.Colors.cardAlt)
        .cornerRadius(10)
    }
}
