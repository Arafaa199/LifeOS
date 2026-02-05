import SwiftUI

struct FinancePlanView: View {
    @ObservedObject var viewModel: FinanceViewModel

    var body: some View {
        ScrollView {
            FinancePlanContent(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.refresh()
            viewModel.loadRecurringItems()
            viewModel.loadFinancialPlanning()
        }
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
