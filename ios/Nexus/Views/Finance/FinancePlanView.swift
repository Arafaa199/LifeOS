import SwiftUI

struct FinancePlanView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingAddRecurring = false
    @State private var editingItem: RecurringItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                obligationsSection
                budgetsSection
                projectionSection
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
            viewModel.loadRecurringItems()
        }
        .sheet(isPresented: $showingAddRecurring) {
            RecurringItemFormView(viewModel: viewModel, editingItem: nil)
        }
        .sheet(item: $editingItem) { item in
            RecurringItemFormView(viewModel: viewModel, editingItem: item)
        }
    }

    // MARK: - Monthly Obligations

    private var obligationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Obligations")
                        .font(.headline)
                    Text(formatCurrency(viewModel.monthlyObligations, currency: AppSettings.shared.defaultCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                Spacer()
                Button(action: { showingAddRecurring = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.nexusFinance)
                }
            }

            if viewModel.upcomingBills.isEmpty {
                Text("No recurring items. Tap + to add bills and subscriptions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.upcomingBills) { item in
                    RecurringItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = item }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteRecurringItem(id: item.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                if !viewModel.recurringIncome.isEmpty {
                    Divider()
                    Text("Recurring Income")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach(viewModel.recurringIncome) { item in
                        RecurringItemRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { editingItem = item }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Budgets

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budgets")
                .font(.headline)

            let budgets = viewModel.summary.budgets
            if budgets.isEmpty {
                Text("No budgets set.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                let sorted = budgets.sorted { (($0.spent ?? 0) / max($0.budgetAmount, 1)) > (($1.spent ?? 0) / max($1.budgetAmount, 1)) }
                ForEach(sorted, id: \.category) { budget in
                    BudgetCompactRow(budget: budget)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Cashflow Projection

    private var projectionSection: some View {
        let totalIncome = viewModel.summary.totalIncome
        let totalSpent = viewModel.summary.totalSpent
        let remaining = totalIncome - totalSpent

        let calendar = Calendar.current
        let today = Date()
        let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let currentDay = calendar.component(.day, from: today)
        let daysRemaining = daysInMonth - currentDay

        let upcomingObligations = viewModel.upcomingBills
            .filter { item in
                guard let dueDate = item.nextDueDate else { return false }
                let dueDay = calendar.component(.day, from: dueDate)
                let dueMonth = calendar.component(.month, from: dueDate)
                let thisMonth = calendar.component(.month, from: today)
                return dueMonth == thisMonth && dueDay > currentDay
            }
            .reduce(0.0) { $0 + $1.amount }

        let projectedNet = remaining - upcomingObligations

        return VStack(alignment: .leading, spacing: 12) {
            Text("Rest of Month")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remaining balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(remaining, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(remaining >= 0 ? .green : .red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(daysRemaining) days left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if upcomingObligations > 0 {
                        Text("- \(formatCurrency(upcomingObligations, currency: AppSettings.shared.defaultCurrency)) bills")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Divider()

            HStack {
                Text("After obligations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text((projectedNet >= 0 ? "" : "") + formatCurrency(projectedNet, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(projectedNet >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Recurring Item Row

struct RecurringItemRow: View {
    let item: RecurringItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(item.cadenceDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let daysUntil = item.daysUntilDue {
                        Text(dueDateLabel(daysUntil))
                            .font(.caption)
                            .foregroundColor(item.isOverdue ? .red : item.isDueSoon ? .orange : .secondary)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(item.amount, currency: item.currency))
                .font(.headline)
                .foregroundColor(item.isExpense ? .primary : .green)
        }
        .padding(.vertical, 4)
    }

    private func dueDateLabel(_ days: Int) -> String {
        if days == 0 { return "Due today" }
        if days > 0 { return "Due in \(days)d" }
        return "\(-days)d overdue"
    }
}

// MARK: - Budget Compact Row

struct BudgetCompactRow: View {
    let budget: Budget

    var body: some View {
        let spent = budget.spent ?? 0
        let total = budget.budgetAmount
        let pct = total > 0 ? spent / total : 0

        VStack(spacing: 6) {
            HStack {
                Text(budget.category.capitalized)
                    .font(.subheadline)
                Spacer()
                Text("\(formatCurrency(spent, currency: "AED")) / \(formatCurrency(total, currency: "AED"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 4)
                        .cornerRadius(2)
                    Rectangle()
                        .fill(pct > 1 ? Color.red : pct > 0.8 ? Color.orange : Color.nexusFinance)
                        .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}
