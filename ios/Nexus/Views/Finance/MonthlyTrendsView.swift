import SwiftUI
import Charts

struct MonthlyTrendsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    @State private var monthlyData: [MonthlySpending] = []
    @State private var isLoading = false
    @State private var selectedPeriod: Period = .last3Months

    enum Period: String, CaseIterable {
        case last3Months = "3 Months"
        case last6Months = "6 Months"
        case last12Months = "12 Months"

        var monthsCount: Int {
            switch self {
            case .last3Months: return 3
            case .last6Months: return 6
            case .last12Months: return 12
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Period selector
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(Period.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedPeriod) { _ in
                        Task {
                            await loadMonthlyData()
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if !monthlyData.isEmpty {
                        // Spending trend chart
                        spendingTrendChart

                        // Month comparison cards
                        monthComparisonCards

                        // Category trends
                        categoryTrendsSection
                    } else {
                        Text("No data available")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Monthly Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task {
                    await loadMonthlyData()
                }
            }
        }
    }

    @ViewBuilder
    private var spendingTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Trend")
                .font(.headline)
                .padding(.horizontal)

            if #available(iOS 16.0, *) {
                Chart(monthlyData) { item in
                    LineMark(
                        x: .value("Month", item.monthName),
                        y: .value("Amount", item.totalSpent)
                    )
                    .foregroundStyle(Color.nexusFinance)
                    .symbol(Circle())

                    AreaMark(
                        x: .value("Month", item.monthName),
                        y: .value("Amount", item.totalSpent)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.nexusFinance.opacity(0.3), Color.nexusFinance.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 200)
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                // Fallback for iOS 15
                VStack(spacing: 8) {
                    ForEach(monthlyData) { item in
                        HStack {
                            Text(item.monthName)
                                .font(.subheadline)
                                .frame(width: 60, alignment: .leading)

                            GeometryReader { geometry in
                                let maxSpending = monthlyData.map { $0.totalSpent }.max() ?? 1
                                let width = (item.totalSpent / maxSpending) * geometry.size.width

                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color(.tertiarySystemBackground))
                                        .frame(height: 24)

                                    Rectangle()
                                        .fill(Color.nexusPrimary)
                                        .frame(width: width, height: 24)
                                }
                                .cornerRadius(4)
                            }
                            .frame(height: 24)

                            Text(String(format: "%.0f", item.totalSpent))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private var monthComparisonCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month Comparison")
                .font(.headline)
                .padding(.horizontal)

            if monthlyData.count >= 2 {
                let current = monthlyData.last!
                let previous = monthlyData[monthlyData.count - 2]
                let change = current.totalSpent - previous.totalSpent
                let percentChange = (change / previous.totalSpent) * 100

                HStack(spacing: 12) {
                    MonthCard(
                        month: current.monthName,
                        amount: current.totalSpent,
                        isCurrent: true
                    )

                    VStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(change >= 0 ? .nexusError : .nexusSuccess)
                        Text(String(format: "%.0f%%", abs(percentChange)))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(change >= 0 ? .nexusError : .nexusSuccess)
                    }
                    .frame(width: 60)

                    MonthCard(
                        month: previous.monthName,
                        amount: previous.totalSpent,
                        isCurrent: false
                    )
                }
                .padding(.horizontal)
            }
        }
    }

    private var categoryTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Categories This Period")
                .font(.headline)
                .padding(.horizontal)

            if let currentMonth = monthlyData.last {
                ForEach(Array(currentMonth.categoryBreakdown.sorted(by: { $0.value > $1.value }).prefix(5)), id: \.key) { category, amount in
                    HStack {
                        Text(category)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "AED %.0f", amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        // Show trend indicator
                        if monthlyData.count >= 2 {
                            let previousMonth = monthlyData[monthlyData.count - 2]
                            let previousAmount = previousMonth.categoryBreakdown[category] ?? 0
                            let change = amount - previousAmount

                            if change != 0 {
                                Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption)
                                    .foregroundColor(change > 0 ? .nexusError : .nexusSuccess)
                            }
                        }
                    }
                    .padding()
                    .background(Color.nexusCardBackground)
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadMonthlyData() async {
        isLoading = true

        do {
            let response = try await NexusAPI.shared.fetchMonthlyTrends(months: selectedPeriod.monthsCount)
            if response.success, let data = response.data {
                monthlyData = data.monthlySpending
            }
        } catch {
            #if DEBUG
            print("Failed to load monthly trends: \(error)")
            #endif
        }

        isLoading = false
    }
}

struct MonthCard: View {
    let month: String
    let amount: Double
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(month)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "AED %.0f", amount))
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(isCurrent ? Color.nexusPrimary.opacity(0.1) : Color.nexusCardBackground)
        .cornerRadius(12)
    }
}

#Preview {
    MonthlyTrendsView(viewModel: FinanceViewModel())
}
