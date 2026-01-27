import SwiftUI
import Combine

struct FinanceBudgetsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingBudgetSettings = false

    private var sortedBudgets: [Budget] {
        viewModel.summary.budgets.sorted { budget1, budget2 in
            // Sort by percentage used (descending)
            let pct1 = (budget1.spent ?? 0) / max(budget1.budgetAmount, 1)
            let pct2 = (budget2.spent ?? 0) / max(budget2.budgetAmount, 1)
            return pct1 > pct2
        }
    }

    private var totalBudget: Double {
        viewModel.summary.budgets.reduce(0) { $0 + $1.budgetAmount }
    }

    private var totalSpent: Double {
        viewModel.summary.budgets.reduce(0) { $0 + ($1.spent ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Freshness indicator
                HStack(spacing: 6) {
                    if let freshness = viewModel.financeFreshness {
                        Circle()
                            .fill(freshness.isStale ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? .orange : .secondary)
                    } else if let lastUpdated = viewModel.lastUpdated {
                        Circle()
                            .fill(viewModel.isOffline ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text("Updated \(lastUpdated, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if viewModel.isOffline {
                        Text("(Offline)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Overall budget summary
                if !viewModel.summary.budgets.isEmpty {
                    overallSummaryCard
                }

                // Individual budgets
                if viewModel.summary.budgets.isEmpty {
                    emptyState
                } else {
                    budgetsList
                }

                // Manage budgets button
                manageBudgetsButton
            }
            .padding()
        }
        .sheet(isPresented: $showingBudgetSettings) {
            BudgetSettingsView()
        }
    }

    // MARK: - Overall Summary Card

    private var overallSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Budget")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(totalBudget, currency: AppSettings.shared.defaultCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Spent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(totalSpent, currency: AppSettings.shared.defaultCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(totalSpent > totalBudget ? .red : .primary)
                }
            }

            // Progress bar
            let progress = totalBudget > 0 ? min(totalSpent / totalBudget, 1.2) : 0
            let isOver = totalSpent > totalBudget

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 10)
                            .cornerRadius(5)

                        Rectangle()
                            .fill(isOver ? Color.red : Color.nexusFinance)
                            .frame(width: geo.size.width * min(progress, 1.0), height: 10)
                            .cornerRadius(5)
                    }
                }
                .frame(height: 10)

                HStack {
                    let remaining = totalBudget - totalSpent
                    if remaining >= 0 {
                        Text(formatCurrency(remaining, currency: AppSettings.shared.defaultCurrency) + " remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(formatCurrency(abs(remaining), currency: AppSettings.shared.defaultCurrency) + " over budget")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isOver ? .red : .secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Budgets List

    private var budgetsList: some View {
        VStack(spacing: 12) {
            ForEach(sortedBudgets) { budget in
                BudgetRowCard(budget: budget)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No budgets set")
                .font(.headline)

            Text("Set monthly budgets to track spending by category")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Manage Budgets Button

    private var manageBudgetsButton: some View {
        Button(action: { showingBudgetSettings = true }) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text(viewModel.summary.budgets.isEmpty ? "Set Budgets" : "Manage Budgets")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.nexusFinance)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}

// MARK: - Budget Row Card

struct BudgetRowCard: View {
    let budget: Budget

    private var spent: Double {
        budget.spent ?? 0
    }

    private var progress: Double {
        min(spent / max(budget.budgetAmount, 1), 1.2)
    }

    private var isOverBudget: Bool {
        spent > budget.budgetAmount
    }

    private var remaining: Double {
        budget.budgetAmount - spent
    }

    private var progressColor: Color {
        if isOverBudget { return .red }
        if progress > 0.8 { return .orange }
        return .nexusFinance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: categoryIcon)
                        .foregroundColor(progressColor)
                    Text(budget.category.capitalized)
                        .font(.headline)
                }

                Spacer()

                // Status badge
                if isOverBudget {
                    Text("OVER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .cornerRadius(4)
                }
            }

            // Amount row
            HStack {
                Text(formatCurrency(spent, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .foregroundColor(isOverBudget ? .red : .primary)

                Text("of")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formatCurrency(budget.budgetAmount, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if remaining >= 0 {
                    Text(formatCurrency(remaining, currency: AppSettings.shared.defaultCurrency) + " left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(formatCurrency(abs(remaining), currency: AppSettings.shared.defaultCurrency) + " over")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var categoryIcon: String {
        switch budget.category.lowercased() {
        case "grocery", "groceries": return "cart.fill"
        case "restaurant", "food", "eating out": return "fork.knife"
        case "transport", "transportation": return "car.fill"
        case "utilities": return "house.fill"
        case "entertainment": return "tv.fill"
        case "health": return "heart.fill"
        case "shopping": return "bag.fill"
        case "rent": return "building.2.fill"
        case "subscriptions": return "arrow.triangle.2.circlepath"
        default: return "chart.bar.fill"
        }
    }
}

#Preview {
    FinanceBudgetsView(viewModel: FinanceViewModel())
}
