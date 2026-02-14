import SwiftUI
import Combine
import UIKit

struct FinanceBudgetsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingBudgetSettings = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)

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
                            .fill(freshness.isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? NexusTheme.Colors.Semantic.amber : .secondary)
                    } else if let lastUpdated = viewModel.lastUpdated,
                              Date().timeIntervalSince(lastUpdated) > 300 || viewModel.isOffline {
                        Circle()
                            .fill(viewModel.isOffline ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                            .frame(width: 6, height: 6)
                        Text("Updated \(lastUpdated, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if viewModel.isOffline {
                        Text("(Offline)")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
        .refreshable {
            await viewModel.refresh()
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
                        .foregroundColor(totalSpent > totalBudget ? NexusTheme.Colors.Semantic.red : .primary)
                }
            }

            // Progress bar
            let progress = totalBudget > 0 ? min(totalSpent / totalBudget, 1.2) : 0
            let isOver = totalSpent > totalBudget

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(NexusTheme.Colors.divider)
                            .frame(height: 10)
                            .cornerRadius(5)

                        Rectangle()
                            .fill(isOver ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.green)
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
                            .foregroundColor(NexusTheme.Colors.Semantic.red)
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isOver ? NexusTheme.Colors.Semantic.red : .secondary)
                }
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
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
        ThemeEmptyState(
            icon: "chart.bar.fill",
            headline: "No Budgets Set",
            description: "Set monthly budgets to track spending by category.",
            ctaTitle: "Set Budgets",
            ctaAction: { showingBudgetSettings = true }
        )
    }

    // MARK: - Manage Budgets Button

    private var manageBudgetsButton: some View {
        Button(action: {
            haptics.impactOccurred()
            showingBudgetSettings = true
        }) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text(viewModel.summary.budgets.isEmpty ? "Set Budgets" : "Manage Budgets")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(NexusTheme.Colors.Semantic.green)
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
        if isOverBudget { return NexusTheme.Colors.Semantic.red }
        if progress > 0.8 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.green
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
                        .background(NexusTheme.Colors.Semantic.red)
                        .cornerRadius(4)
                }
            }

            // Amount row
            HStack {
                Text(formatCurrency(spent, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .foregroundColor(isOverBudget ? NexusTheme.Colors.Semantic.red : .primary)

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
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(NexusTheme.Colors.divider)
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
        .background(NexusTheme.Colors.card)
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
