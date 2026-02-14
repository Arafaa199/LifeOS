import SwiftUI
import Charts

struct CashflowProjectionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    @State private var projectedEvents: [ProjectedEvent] = []
    @State private var currentBalance: Double = 0

    private let projectionDays = 30

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header: Balance Summary
                    balanceSummarySection

                    // Chart Section
                    if !projectedEvents.isEmpty {
                        chartSection
                    }

                    // Timeline Section
                    if !projectedEvents.isEmpty {
                        timelineSection
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("30-Day Projection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
                generateProjection()
            }
            .onAppear {
                generateProjection()
            }
        }
    }

    // MARK: - Balance Summary Section

    private var balanceSummarySection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Current Balance (Today)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(formatCurrency(currentBalance, currency: AppSettings.shared.defaultCurrency))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Divider()
                .padding(.vertical, 8)

            let endOfMonthBalance = projectedEvents.last?.runningBalance ?? currentBalance
            let projectedChange = endOfMonthBalance - currentBalance

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projected End-of-Month")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(formatCurrency(endOfMonthBalance, currency: AppSettings.shared.defaultCurrency))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Projected Change")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: projectedChange >= 0 ? "arrow.up.right" : "arrow.down.left")
                            .font(.caption2)
                            .fontWeight(.semibold)

                        Text((projectedChange >= 0 ? "+" : "") + formatCurrency(projectedChange, currency: AppSettings.shared.defaultCurrency))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(projectedChange >= 0 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)
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

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Balance Projection")
                .font(.headline)
                .fontWeight(.semibold)

            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(projectedEvents) { event in
                        LineMark(
                            x: .value("Date", event.date),
                            y: .value("Balance", event.runningBalance)
                        )
                        .foregroundStyle(event.runningBalance >= currentBalance ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", event.date),
                            y: .value("Balance", event.runningBalance)
                        )
                        .foregroundStyle(event.runningBalance >= currentBalance ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                    }

                    // Reference line for current balance
                    RuleMark(y: .value("Today", currentBalance))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                    }
                }
            } else {
                // Fallback for iOS 15
                VStack(alignment: .center, spacing: 12) {
                    Text("30-Day Balance Trend")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 0) {
                        ForEach(projectedEvents.prefix(30), id: \.id) { event in
                            VStack(spacing: 4) {
                                let allValues = projectedEvents.map { $0.runningBalance }
                                let minValue = allValues.min() ?? 0
                                let maxValue = allValues.max() ?? 0
                                let range = max(maxValue - minValue, 1) // Guard against division by zero
                                let ratio = (event.runningBalance - minValue) / range

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(event.runningBalance >= currentBalance ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                                    .frame(height: CGFloat(ratio) * 80 + 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 100)
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

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Transactions")
                .font(.headline)
                .fontWeight(.semibold)

            let groupedByDay = Dictionary(grouping: projectedEvents) { calendar.component(.day, from: $0.date) }

            ForEach(Array(groupedByDay.sorted { $0.key < $1.key }), id: \.key) { day, events in
                VStack(alignment: .leading, spacing: 0) {
                    // Date header
                    let date = events.first?.date ?? Date()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            let dayOfWeek = calendar.component(.weekday, from: date)
                            let weekdayName = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][dayOfWeek - 1]
                            Text(weekdayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let runningBalance = events.first?.runningBalance {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Balance")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(formatCurrency(runningBalance, currency: AppSettings.shared.defaultCurrency))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(runningBalance >= currentBalance ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                            }
                        }
                    }
                    .padding(.bottom, 12)

                    Divider()

                    // Events for this day
                    ForEach(events.sorted { $0.date < $1.date }) { event in
                        projectionEventRow(event)

                        if event.id != events.sorted(by: { $0.date < $1.date }).last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
                .padding(12)
                .background(NexusTheme.Colors.cardAlt)
                .cornerRadius(10)

                if day != groupedByDay.keys.sorted().last {
                    Divider()
                        .padding(.vertical, 8)
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

    private func projectionEventRow(_ event: ProjectedEvent) -> some View {
        HStack(spacing: 12) {
            // Type indicator
            Circle()
                .fill(event.type == .income ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)
                .frame(width: 10, height: 10)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Amount
            HStack(spacing: 4) {
                Text(event.type == .income ? "+" : "")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(event.type == .income ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)

                Text(formatCurrency(event.amount, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(event.type == .income ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ThemeEmptyState(
            icon: "chart.line.uptrend.xyaxis",
            headline: "No upcoming transactions",
            description: "Add recurring income and expenses to see a 30-day projection of your cash balance."
        )
        .themeCard()
    }

    // MARK: - Projection Logic

    private func generateProjection() {
        let today = Date()
        var events: [ProjectedEvent] = []

        // Initialize current balance from summary
        currentBalance = viewModel.summary.totalIncome - viewModel.summary.totalSpent

        // Add recurring expenses
        for item in viewModel.upcomingBills {
            let startDate = item.nextDueDate ?? today
            let calendar = Calendar.current
            var currentDate = startDate

            while calendar.dateComponents([.day], from: today, to: currentDate).day ?? 0 < projectionDays {
                if currentDate >= today {
                    events.append(ProjectedEvent(
                        date: currentDate,
                        description: item.name,
                        amount: item.amount,
                        type: .expense
                    ))
                }

                // Calculate next occurrence based on cadence
                currentDate = nextOccurrenceDate(from: currentDate, cadence: item.cadence)
            }
        }

        // Add recurring income
        for item in viewModel.recurringIncome {
            let startDate = item.nextDueDate ?? today
            let calendar = Calendar.current
            var currentDate = startDate

            while calendar.dateComponents([.day], from: today, to: currentDate).day ?? 0 < projectionDays {
                if currentDate >= today {
                    events.append(ProjectedEvent(
                        date: currentDate,
                        description: item.name,
                        amount: item.amount,
                        type: .income
                    ))
                }

                // Calculate next occurrence
                currentDate = nextOccurrenceDate(from: currentDate, cadence: item.cadence)
            }
        }

        // Sort by date
        events.sort { $0.date < $1.date }

        // Calculate running balance
        var balance = currentBalance
        for i in 0..<events.count {
            if events[i].type == .income {
                balance += events[i].amount
            } else {
                balance -= events[i].amount
            }
            events[i].runningBalance = balance
        }

        self.projectedEvents = events
    }

    private func nextOccurrenceDate(from date: Date, cadence: String) -> Date {
        let calendar = Calendar.current
        switch cadence {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case "weekly":
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case "biweekly":
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case "quarterly":
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case "yearly":
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        default:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }

    private var calendar: Calendar {
        Calendar.current
    }
}

// MARK: - Projected Event Model

struct ProjectedEvent: Identifiable {
    let id = UUID()
    let date: Date
    let description: String
    let amount: Double
    let type: TransactionType
    var runningBalance: Double = 0

    enum TransactionType {
        case income
        case expense
    }
}

// MARK: - Preview

#Preview {
    CashflowProjectionView(viewModel: FinanceViewModel())
}
