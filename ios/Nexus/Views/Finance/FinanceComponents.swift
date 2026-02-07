import SwiftUI

// MARK: - Budget View

struct BudgetView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingBudgetSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.summary.budgets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No budgets set")
                            .font(.headline)
                        Text("Set monthly budgets to track spending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: {
                            showingBudgetSettings = true
                        }) {
                            Text("Set Budgets")
                                .fontWeight(.semibold)
                                .padding()
                                .background(NexusTheme.Colors.accent)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.top)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(viewModel.summary.budgets) { budget in
                        BudgetCard(budget: budget)
                    }
                }

                // Spending Charts
                if !viewModel.summary.categoryBreakdown.isEmpty {
                    SpendingChartsView(
                        categoryBreakdown: viewModel.summary.categoryBreakdown,
                        totalSpent: viewModel.summary.totalSpent
                    )
                }

                // Category Breakdown (Text List)
                if !viewModel.summary.categoryBreakdown.isEmpty {
                    categoryBreakdownSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingBudgetSettings) {
            BudgetSettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.summary.budgets.isEmpty {
                    Button("Manage") {
                        showingBudgetSettings = true
                    }
                }
            }
        }
    }

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month by Category")
                .font(.headline)

            ForEach(Array(viewModel.summary.categoryBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { category, amount in
                HStack {
                    Text(category.capitalized)
                        .font(.subheadline)
                    Spacer()
                    Text(formatCurrency(amount, currency: AppSettings.shared.defaultCurrency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(NexusTheme.Colors.card)
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: Transaction

    private var formattedDate: String {
        if Constants.Dubai.isDateInToday(transaction.date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = Constants.Dubai.timeZone
        return formatter.string(from: transaction.date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(transaction.merchantName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if transaction.hasCorrection {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                            .font(.caption2)
                    }
                }

                HStack(spacing: 6) {
                    if let category = transaction.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(transaction.amount > 0
                 ? "+\(formatCurrency(abs(transaction.amount), currency: transaction.currency))"
                 : "-\(formatCurrency(abs(transaction.amount), currency: transaction.currency))")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(transaction.amount < 0 ? .primary : NexusTheme.Colors.Semantic.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Budget Card

struct BudgetCard: View {
    let budget: Budget

    private var progress: Double {
        guard let spent = budget.spent else { return 0 }
        return min(spent / budget.budgetAmount, 1.0)
    }

    private var isOverBudget: Bool {
        guard let spent = budget.spent else { return false }
        return spent > budget.budgetAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(budget.category.capitalized)
                    .font(.headline)
                Spacer()
                Text("\(formatCurrency(budget.spent ?? 0, currency: AppSettings.shared.defaultCurrency)) / \(formatCurrency(budget.budgetAmount, currency: AppSettings.shared.defaultCurrency))")
                    .font(.subheadline)
                    .foregroundColor(isOverBudget ? NexusTheme.Colors.Semantic.red : .secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(isOverBudget ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.green)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            if let remaining = budget.remaining {
                Text(remaining >= 0 ?
                     "\(formatCurrency(remaining, currency: AppSettings.shared.defaultCurrency)) remaining" :
                     "\(formatCurrency(abs(remaining), currency: AppSettings.shared.defaultCurrency)) over budget")
                    .font(.caption)
                    .foregroundColor(remaining >= 0 ? .secondary : NexusTheme.Colors.Semantic.red)
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.card)
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
