import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var insights: String = ""
    @State private var isLoadingInsights = false
    @State private var showingMonthlyTrends = false
    @State private var cachedRecurringPatterns: [RecurringPattern] = []
    @State private var cachedTopMerchants: [(merchant: String, total: Double, count: Int)] = []
    @State private var cachedDuplicateGroups: [[Transaction]] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Spending Summary Card (at-a-glance health)
                spendingSummaryCard

                // Potential Duplicates Warning
                if !cachedDuplicateGroups.isEmpty {
                    duplicatesSection
                }

                // Quick Stats
                quickStatsSection

                // Top Merchants
                topMerchantsSection

                // Monthly Trends Button
                Button(action: { showingMonthlyTrends = true }) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("View Monthly Trends")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.nexusCardBackground)
                    .cornerRadius(12)
                }

                // AI Insights
                aiInsightsSection

                // Spending Patterns
                spendingPatternsSection

                // Recurring Transactions
                if !cachedRecurringPatterns.isEmpty {
                    recurringTransactionsSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingMonthlyTrends) {
            MonthlyTrendsView(viewModel: viewModel)
        }
        .onAppear {
            updateCachedComputations()
            if insights.isEmpty {
                Task {
                    await loadInsights()
                }
            }
        }
        .onChange(of: viewModel.recentTransactions.count) { _, _ in
            updateCachedComputations()
        }
    }

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Transactions",
                    value: "\(viewModel.recentTransactions.count)",
                    icon: "list.bullet",
                    color: .nexusPrimary
                )

                StatCard(
                    title: "Avg/Transaction",
                    value: averageTransactionAmount,
                    icon: "chart.bar",
                    color: .nexusSuccess
                )

                StatCard(
                    title: "Categories",
                    value: "\(uniqueCategoriesCount)",
                    icon: "folder",
                    color: .nexusWarning
                )

                StatCard(
                    title: "This Month",
                    value: viewModel.summary.formatAmount(viewModel.summary.totalSpent),
                    icon: "calendar",
                    color: .nexusMood
                )
            }
        }
    }

    private var spendingSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spending Summary")
                        .font(.headline)
                    Text(currentMonthName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                spendingHealthIndicator
            }

            // Main spending figure
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(viewModel.summary.formatAmount(viewModel.summary.totalSpent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("spent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Budget progress (if budgets exist)
            if let totalBudget = totalBudgetAmount, totalBudget > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Budget")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(budgetPercentage))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(budgetStatusColor)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(budgetStatusColor)
                                .frame(width: min(geometry.size.width * budgetPercentage / 100, geometry.size.width), height: 8)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(viewModel.summary.formatAmount(viewModel.summary.totalSpent))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.summary.formatAmount(totalBudget))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Daily pace indicator
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily avg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(dailyAverageAmount)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Divider()
                    .frame(height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Days tracked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(daysWithTransactions)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Divider()
                    .frame(height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top category")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(topCategoryName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.nexusPrimary.opacity(0.1), Color.nexusMood.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.nexusPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var spendingHealthIndicator: some View {
        let health = spendingHealth
        HStack(spacing: 4) {
            Circle()
                .fill(health.color)
                .frame(width: 8, height: 8)
            Text(health.label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(health.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(health.color.opacity(0.15))
        .cornerRadius(12)
    }

    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private var totalBudgetAmount: Double? {
        guard !viewModel.summary.budgets.isEmpty else { return nil }
        return viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
    }

    private var budgetPercentage: Double {
        guard let totalBudget = totalBudgetAmount, totalBudget > 0 else { return 0 }
        return (viewModel.summary.totalSpent / totalBudget) * 100
    }

    private var budgetStatusColor: Color {
        if budgetPercentage >= 100 { return .nexusError }
        if budgetPercentage >= 80 { return .nexusWarning }
        return .nexusSuccess
    }

    private var dailyAverageAmount: String {
        guard !viewModel.recentTransactions.isEmpty else { return "AED 0" }
        let calendar = Calendar.current
        let uniqueDays = Set(viewModel.recentTransactions.map { calendar.startOfDay(for: $0.date) }).count
        guard uniqueDays > 0 else { return "AED 0" }
        let avg = viewModel.summary.totalSpent / Double(uniqueDays)
        return String(format: "AED %.0f", avg)
    }

    private var daysWithTransactions: Int {
        let calendar = Calendar.current
        return Set(viewModel.recentTransactions.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var topCategoryName: String {
        guard let top = viewModel.summary.categoryBreakdown.max(by: { $0.value < $1.value }) else {
            return "N/A"
        }
        return top.key
    }

    private var spendingHealth: (label: String, color: Color) {
        // Determine health based on budget usage and spending patterns
        if let _ = totalBudgetAmount {
            if budgetPercentage >= 100 {
                return ("Over Budget", .nexusError)
            } else if budgetPercentage >= 80 {
                return ("Near Limit", .nexusWarning)
            } else if budgetPercentage >= 50 {
                return ("On Track", .nexusPrimary)
            } else {
                return ("Under Budget", .nexusSuccess)
            }
        }
        // No budgets set - just show neutral status
        return ("Tracking", .nexusPrimary)
    }

    private var topMerchantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.headline)

            ForEach(cachedTopMerchants.prefix(5), id: \.merchant) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.merchant)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(item.count) transaction\(item.count > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(String(format: "AED %.2f", item.total))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(8)
            }
        }
    }

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Insights")
                    .font(.headline)
                Spacer()
                if isLoadingInsights {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        Task {
                            await loadInsights()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }

            if !insights.isEmpty {
                Text(insights)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.nexusPrimary.opacity(0.1))
                    .cornerRadius(12)
            } else if !isLoadingInsights {
                Button(action: {
                    Task {
                        await loadInsights()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate AI Insights")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.nexusPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
    }

    private var spendingPatternsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Patterns")
                .font(.headline)

            VStack(spacing: 12) {
                PatternCard(
                    icon: "clock",
                    title: "Most Active Day",
                    value: mostActiveDay,
                    color: .nexusPrimary
                )

                PatternCard(
                    icon: "calendar.badge.clock",
                    title: "Average Daily Spend",
                    value: averageDailySpend,
                    color: .nexusSuccess
                )

                PatternCard(
                    icon: "chart.pie",
                    title: "Largest Category",
                    value: largestCategory,
                    color: .nexusWarning
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var averageTransactionAmount: String {
        guard !viewModel.recentTransactions.isEmpty else { return "AED 0" }
        let avg = viewModel.recentTransactions.map { abs($0.amount) }.reduce(0, +) / Double(viewModel.recentTransactions.count)
        return String(format: "AED %.0f", avg)
    }

    private var uniqueCategoriesCount: Int {
        Set(viewModel.recentTransactions.compactMap { $0.category }).count
    }

    private var mostActiveDay: String {
        let calendar = Calendar.current
        let dayGroups = Dictionary(grouping: viewModel.recentTransactions) { transaction in
            calendar.component(.weekday, from: transaction.date)
        }
        let mostActive = dayGroups.max { $0.value.count < $1.value.count }
        if let day = mostActive?.key {
            let formatter = DateFormatter()
            return formatter.weekdaySymbols[day - 1]
        }
        return "N/A"
    }

    private var averageDailySpend: String {
        guard !viewModel.recentTransactions.isEmpty else { return "AED 0" }
        let calendar = Calendar.current
        let dayGroups = Dictionary(grouping: viewModel.recentTransactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        let totalDays = dayGroups.count
        let totalSpent = viewModel.recentTransactions.map { abs($0.amount) }.reduce(0, +)
        let avg = totalSpent / Double(totalDays)
        return String(format: "AED %.0f", avg)
    }

    private var largestCategory: String {
        guard !viewModel.summary.categoryBreakdown.isEmpty else { return "N/A" }
        let largest = viewModel.summary.categoryBreakdown.max { $0.value < $1.value }
        if let category = largest?.key, let amount = largest?.value {
            return "\(category) (AED \(String(format: "%.0f", amount)))"
        }
        return "N/A"
    }

    private func updateCachedComputations() {
        cachedTopMerchants = computeTopMerchants()
        cachedRecurringPatterns = viewModel.detectRecurringTransactions()
        cachedDuplicateGroups = viewModel.detectDuplicateTransactions()
    }

    private func computeTopMerchants() -> [(merchant: String, total: Double, count: Int)] {
        let grouped = Dictionary(grouping: viewModel.recentTransactions, by: { $0.merchantName })
        return grouped.map { merchant, transactions in
            let total = transactions.map { abs($0.amount) }.reduce(0, +)
            return (merchant, total, transactions.count)
        }.sorted { $0.total > $1.total }
    }

    private var recurringTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recurring Transactions")
                .font(.headline)

            Text("Detected subscriptions and recurring payments")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(cachedRecurringPatterns.prefix(5)) { pattern in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pattern.merchant)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(.caption2)
                            Text(pattern.frequency.rawValue)
                                .font(.caption)
                            Text("•")
                                .font(.caption)
                            Text("\(pattern.count) times")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "AED %.0f", pattern.amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("per payment")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(8)
            }
        }
    }

    private var duplicatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            duplicatesSectionHeader

            Text("Transactions with same merchant and amount within 1 day")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(Array(cachedDuplicateGroups.prefix(5).enumerated()), id: \.offset) { _, group in
                DuplicateGroupRow(group: group)
            }

            if cachedDuplicateGroups.count > 5 {
                Text("Showing 5 of \(cachedDuplicateGroups.count) groups")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var duplicatesSectionHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.nexusWarning)
            Text("Potential Duplicates")
                .font(.headline)
            Spacer()
            Text("\(cachedDuplicateGroups.count) group\(cachedDuplicateGroups.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Methods

    private func loadInsights() async {
        isLoadingInsights = true

        // Prepare transaction summary for AI
        let summary = generateTransactionSummary()

        // Call AI insights endpoint
        do {
            let response = try await NexusAPI.shared.getSpendingInsights(summary: summary)
            if response.success, let data = response.data {
                insights = data.insights ?? "No insights available"
            }
        } catch {
            insights = "Could not generate insights. Please try again."
        }

        isLoadingInsights = false
    }

    private func generateTransactionSummary() -> String {
        var summary = "Recent spending summary:\n"
        summary += "Total spent: \(viewModel.summary.formatAmount(viewModel.summary.totalSpent))\n"
        summary += "Number of transactions: \(viewModel.recentTransactions.count)\n\n"

        summary += "Category breakdown:\n"
        for (category, amount) in viewModel.summary.categoryBreakdown.sorted(by: { $0.value > $1.value }) {
            summary += "- \(category): AED \(String(format: "%.2f", amount))\n"
        }

        if !viewModel.summary.budgets.isEmpty {
            summary += "\nBudget status:\n"
            for budget in viewModel.summary.budgets {
                let spent = budget.spent ?? 0
                let percentage = (spent / budget.budgetAmount) * 100
                summary += "- \(budget.category): \(String(format: "%.0f%%", percentage)) used\n"
            }
        }

        return summary
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }
}

struct PatternCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(8)
    }
}

struct DuplicateGroupRow: View {
    let group: [Transaction]

    var body: some View {
        if let first = group.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(first.merchantName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(group.count) transactions")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(first.displayAmount)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("each")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                duplicateDates
            }
            .padding()
            .background(Color.nexusWarning.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.nexusWarning.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var duplicateDates: some View {
        HStack(spacing: 4) {
            ForEach(group.prefix(3)) { transaction in
                Text(transaction.date, style: .date)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.nexusWarning.opacity(0.2))
                    .cornerRadius(4)
            }
            if group.count > 3 {
                Text("+\(group.count - 3)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
