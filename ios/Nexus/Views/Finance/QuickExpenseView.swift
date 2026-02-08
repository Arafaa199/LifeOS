import SwiftUI
import UIKit

struct QuickExpenseView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var expenseText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var isSubmitting = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    private var overBudgetCategories: [Budget] {
        viewModel.summary.budgets.filter { budget in
            guard let spent = budget.spent, budget.budgetAmount > 0 else { return false }
            return spent > budget.budgetAmount
        }
    }

    private var nearBudgetCategories: [Budget] {
        viewModel.summary.budgets.filter { budget in
            guard let spent = budget.spent, budget.budgetAmount > 0 else { return false }
            let percentage = spent / budget.budgetAmount
            return percentage >= 0.8 && percentage <= 1.0
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Budget Alerts
                if !overBudgetCategories.isEmpty {
                    budgetAlertBanner(categories: overBudgetCategories, isOverBudget: true)
                } else if !nearBudgetCategories.isEmpty {
                    budgetAlertBanner(categories: nearBudgetCategories, isOverBudget: false)
                }

                // Today's Spending Summary
                summaryCard

                // Quick Log Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Expense")
                        .font(.headline)

                    VStack(spacing: 12) {
                        TextField("e.g., 45 at Carrefour", text: $expenseText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                submitExpense()
                            }
                            .accessibilityLabel("Expense amount")
                            .accessibilityHint("Enter amount and description, for example: 45 groceries at Carrefour")

                        Text("Try: \"45 groceries at Carrefour\" or \"spent 12 on coffee\"")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: submitExpense) {
                            if isSubmitting || viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    Text("Saving...")
                                        .padding(.leading, 4)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Log Expense")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Log expense")
                        .accessibilityHint("Double tap to log this expense")
                        .disabled(expenseText.isEmpty || isSubmitting || viewModel.isLoading)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)

                // Category Quick Actions
                categoryQuickActions

                // Manual Entry Buttons
                HStack(spacing: 12) {
                    Button {
                        haptics.impactOccurred()
                        showingAddExpense = true
                    } label: {
                        HStack {
                            Image(systemName: "minus.circle.fill")
                            Text("Add Expense")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(NexusTheme.Colors.Semantic.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: NexusTheme.Colors.Semantic.red.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .accessibilityLabel("Add expense")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double tap to open expense entry form")

                    Button {
                        haptics.impactOccurred()
                        showingAddIncome = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Income")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(NexusTheme.Colors.Semantic.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: NexusTheme.Colors.Semantic.green.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .accessibilityLabel("Add income")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double tap to open income entry form")
                }

                // Recent Transactions
                if !viewModel.recentTransactions.isEmpty {
                    recentTransactionsSection
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                        .padding()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddIncome) {
            IncomeView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadFinanceSummary()
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's Spending")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(viewModel.summary.formatAmount(viewModel.summary.totalSpent))
                        .font(.system(size: 32, weight: .bold))
                }
                Spacer()
            }

            HStack(spacing: 20) {
                StatItem(
                    icon: "cart.fill",
                    label: "Grocery",
                    value: viewModel.summary.formatAmount(viewModel.summary.grocerySpent),
                    color: NexusTheme.Colors.Semantic.green
                )

                StatItem(
                    icon: "fork.knife",
                    label: "Eating Out",
                    value: viewModel.summary.formatAmount(viewModel.summary.eatingOutSpent),
                    color: NexusTheme.Colors.Semantic.amber
                )
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }

    private var categoryQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Categories")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    Button(action: {
                        expenseText = category.rawValue
                        isTextFieldFocused = true
                    }) {
                        HStack {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.rawValue) category")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double tap to select \(category.rawValue) as expense category")
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
    }

    private func submitExpense() {
        // Prevent double-submit
        guard !isSubmitting else { return }

        haptics.impactOccurred()
        isSubmitting = true

        Task {
            let success = await viewModel.logExpense(expenseText)

            if success {
                successHaptics.notificationOccurred(.success)
                expenseText = ""
            } else {
                successHaptics.notificationOccurred(.error)
            }

            isSubmitting = false
            isTextFieldFocused = false
        }
    }

    @ViewBuilder
    private func budgetAlertBanner(categories: [Budget], isOverBudget: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isOverBudget ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(isOverBudget ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.amber)
                Text(isOverBudget ? "Over Budget" : "Budget Warning")
                    .font(.headline)
                    .foregroundColor(isOverBudget ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.amber)
                Spacer()
            }

            ForEach(categories) { budget in
                HStack {
                    Text(budget.category.capitalized)
                        .font(.subheadline)
                    Spacer()
                    if let spent = budget.spent {
                        if isOverBudget {
                            Text("\(formatCurrency(spent - budget.budgetAmount, currency: AppSettings.shared.defaultCurrency)) over")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            let percentage = (spent / budget.budgetAmount) * 100
                            Text(String(format: "%.0f%% used", percentage))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .foregroundColor(isOverBudget ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.amber)
            }
        }
        .padding()
        .background(isOverBudget ? NexusTheme.Colors.Semantic.red.opacity(0.1) : NexusTheme.Colors.Semantic.amber.opacity(0.1))
        .cornerRadius(12)
    }
}
