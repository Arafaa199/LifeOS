import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var insights: String = ""
    @State private var isLoadingInsights = false
    @State private var showingMonthlyTrends = false
    @State private var cachedRecurringPatterns: [RecurringPattern] = []
    @State private var cachedTopMerchants: [(merchant: String, total: Double, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                    .background(Color(.secondarySystemBackground))
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
                    color: .blue
                )

                StatCard(
                    title: "Avg/Transaction",
                    value: averageTransactionAmount,
                    icon: "chart.bar",
                    color: .green
                )

                StatCard(
                    title: "Categories",
                    value: "\(uniqueCategoriesCount)",
                    icon: "folder",
                    color: .orange
                )

                StatCard(
                    title: "This Month",
                    value: viewModel.summary.formatAmount(viewModel.summary.totalSpent),
                    icon: "calendar",
                    color: .purple
                )
            }
        }
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
                .background(Color(.secondarySystemBackground))
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
                    .background(Color.blue.opacity(0.1))
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
                    .background(Color.blue)
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
                    color: .blue
                )

                PatternCard(
                    icon: "calendar.badge.clock",
                    title: "Average Daily Spend",
                    value: averageDailySpend,
                    color: .green
                )

                PatternCard(
                    icon: "chart.pie",
                    title: "Largest Category",
                    value: largestCategory,
                    color: .orange
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
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
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
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}
