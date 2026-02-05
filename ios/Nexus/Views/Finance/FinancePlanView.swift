import SwiftUI

struct FinancePlanView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingAddRecurring = false
    @State private var editingItem: RecurringItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                snapshotCard
                SpendLimitCard(viewModel: viewModel)

                if !viewModel.activeDebts.isEmpty {
                    debtsCard
                }

                obligationsSection
                budgetsSection
                projectionSection

                if viewModel.wishlistItems.contains(where: { $0.status == "wanted" || $0.status == "saving" }) {
                    wishlistPreview
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
            viewModel.loadRecurringItems()
            viewModel.loadFinancialPlanning()
        }
        .sheet(isPresented: $showingAddRecurring) {
            RecurringItemFormView(viewModel: viewModel, editingItem: nil)
        }
        .sheet(item: $editingItem) { item in
            RecurringItemFormView(viewModel: viewModel, editingItem: item)
        }
        .onAppear {
            viewModel.loadFinancialPlanning()
        }
    }

    // MARK: - Financial Snapshot

    private var snapshotCard: some View {
        let income = viewModel.summary.totalIncome
        let fixed = viewModel.monthlyObligations
        let debtPayments = viewModel.monthlyDebtPayments
        let available = income - fixed - debtPayments

        return VStack(spacing: 12) {
            HStack {
                Text("Financial Snapshot")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 0) {
                snapshotStat("Income", value: income, color: .nexusSuccess)
                Spacer()
                snapshotStat("Fixed", value: fixed, color: .nexusWarning)
                Spacer()
                snapshotStat("Debt", value: debtPayments, color: .nexusError)
                Spacer()
                snapshotStat("Available", value: available, color: available >= 0 ? .nexusPrimary : .nexusError)
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    private func snapshotStat(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(formatCompact(value))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Debts Summary Card

    private var debtsCard: some View {
        NavigationLink(destination: DebtsListView(viewModel: viewModel)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.nexusMood)
                    Text("Debts & Payments")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatCurrency(viewModel.totalDebtRemaining, currency: AppSettings.shared.defaultCurrency))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("\(viewModel.activeDebts.count) active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let next = viewModel.nextDebtDue {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(next.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            if let date = next.nextDueDate {
                                Text(formatShortDate(date))
                                    .font(.caption)
                                    .foregroundColor(next.isOverdue ? .nexusError : next.isDueSoon ? .nexusWarning : .secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
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
                        .foregroundColor(.nexusError)
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
        .background(Color.nexusCardBackground)
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
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Cashflow Outlook

    private var projectionSection: some View {
        let totalIncome = viewModel.summary.totalIncome
        let totalSpent = viewModel.summary.totalSpent
        let remaining = totalIncome - totalSpent
        let debtPaymentsRemaining = viewModel.activeDebts
            .filter { debt in
                guard let date = debt.nextDueDate else { return false }
                return date > Date() && Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
            }
            .reduce(0.0) { $0 + $1.monthlyPayment }

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

        let projectedNet = remaining - upcomingObligations - debtPaymentsRemaining

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cashflow Outlook")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: CashflowProjectionView(viewModel: viewModel)) {
                    HStack(spacing: 4) {
                        Text("Full Projection")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.nexusFinance)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remaining balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(remaining, currency: AppSettings.shared.defaultCurrency))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(remaining >= 0 ? .nexusSuccess : .nexusError)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(daysRemaining) days left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if upcomingObligations > 0 {
                        Text("- \(formatCurrency(upcomingObligations, currency: AppSettings.shared.defaultCurrency)) bills")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                    if debtPaymentsRemaining > 0 {
                        Text("- \(formatCurrency(debtPaymentsRemaining, currency: AppSettings.shared.defaultCurrency)) debts")
                            .font(.caption)
                            .foregroundColor(.nexusError)
                    }
                }
            }

            Divider()

            HStack {
                Text("After obligations + debts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatCurrency(projectedNet, currency: AppSettings.shared.defaultCurrency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(projectedNet >= 0 ? .nexusSuccess : .nexusError)
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Wishlist Preview

    private var wishlistPreview: some View {
        let activeItems = viewModel.wishlistItems
            .filter { $0.status == "wanted" || $0.status == "saving" }
            .sorted { $0.priority < $1.priority }

        return NavigationLink(destination: WishlistView(viewModel: viewModel)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "heart.circle.fill")
                        .foregroundColor(.nexusMood)
                    Text("Wishlist")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(activeItems.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(Array(activeItems.prefix(3))) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(formatCurrency(item.estimatedCost, currency: item.currency))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatCompact(_ value: Double) -> String {
        let abs = abs(value)
        let sign = value < 0 ? "-" : ""
        if abs >= 1000 {
            return sign + String(format: "%.1fK", abs / 1000)
        }
        return sign + String(format: "%.0f", abs)
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
                            .foregroundColor(item.isOverdue ? .nexusError : item.isDueSoon ? .nexusWarning : .secondary)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(item.amount, currency: item.currency))
                .font(.headline)
                .foregroundColor(item.isExpense ? .primary : .nexusSuccess)
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
                        .fill(pct > 1 ? Color.nexusError : pct > 0.8 ? Color.nexusWarning : Color.nexusFinance)
                        .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}
