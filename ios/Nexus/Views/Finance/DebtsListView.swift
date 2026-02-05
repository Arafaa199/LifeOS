import SwiftUI

struct DebtsListView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingAddDebt = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.activeDebts.isEmpty {
                    emptyState
                } else {
                    summaryCard
                    if hasOverdue { overdueWarning }
                    debtsList
                }
            }
            .padding()
        }
        .navigationTitle("Debts & Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddDebt = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddDebt) {
            DebtFormView(viewModel: viewModel)
        }
        .refreshable {
            viewModel.loadDebts()
        }
        .onAppear {
            viewModel.loadDebts()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(viewModel.totalDebtRemaining, currency: "AED"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Spacer()
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundColor(.nexusFinance.opacity(0.7))
            }

            Divider()

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.activeDebts.count)")
                        .font(.headline)
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCurrency(viewModel.monthlyDebtPayments, currency: "AED"))
                        .font(.headline)
                    Text("Monthly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let next = viewModel.nextDebtDue, let date = next.nextDueDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatShortDate(date))
                            .font(.headline)
                            .foregroundColor(next.isOverdue ? .nexusError : next.isDueSoon ? .nexusWarning : .primary)
                        Text("Next Due")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Overdue Warning

    private var hasOverdue: Bool {
        viewModel.activeDebts.contains { $0.isOverdue }
    }

    private var overdueWarning: some View {
        let overdueDebts = viewModel.activeDebts.filter { $0.isOverdue }
        let total = overdueDebts.reduce(0) { $0 + $1.monthlyPayment }

        return HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.nexusError)
            Text("\(overdueDebts.count) overdue — \(formatCurrency(total, currency: "AED"))")
                .font(.subheadline)
                .foregroundColor(.nexusError)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.nexusError.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Debts List

    private var debtsList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.activeDebts) { debt in
                debtCard(debt)
            }

            let completed = viewModel.debts.filter { $0.status == "completed" }
            if !completed.isEmpty {
                Divider().padding(.vertical, 8)
                Text("Completed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                ForEach(completed) { debt in
                    completedRow(debt)
                }
            }
        }
    }

    private func debtCard(_ debt: Debt) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(debtColor(debt).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: debt.debtTypeIcon)
                        .font(.system(size: 18))
                        .foregroundColor(debtColor(debt))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(debt.name)
                            .font(.headline)
                        Spacer()
                        Text(formatCurrency(debt.remainingAmount, currency: debt.currency))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(debt.debtTypeLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(debtColor(debt).opacity(0.15))
                            .foregroundColor(debtColor(debt))
                            .cornerRadius(4)

                        if let progress = debt.progressText {
                            Text(progress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if debt.isOverdue {
                            urgencyBadge("OVERDUE", color: .nexusError)
                        } else if debt.isDueSoon {
                            urgencyBadge("DUE SOON", color: .nexusWarning)
                        }
                    }
                }
            }
            .padding()

            // Progress bar
            if let pct = debt.progressPct, pct > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                        Rectangle()
                            .fill(debtColor(debt))
                            .frame(width: geo.size.width * min(pct / 100, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Next payment info
            if let date = debt.nextDueDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Next: \(debt.currency) \(String(format: "%.2f", debt.monthlyPayment)) on \(formatShortDate(date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Pay") {
                        Task { await viewModel.recordDebtPayment(debtId: debt.id) }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.nexusFinance)
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
        }
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }

    private func completedRow(_ debt: Debt) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.nexusSuccess)
            Text(debt.name)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .strikethrough()
            Spacer()
            Text(formatCurrency(debt.originalAmount, currency: debt.currency))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.nexusSuccess)
            Text("No Active Debts")
                .font(.headline)
            Text("Debts, loans, and BNPL plans will be tracked here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddDebt = true }) {
                Label("Add Debt", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func urgencyBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }

    private func debtColor(_ debt: Debt) -> Color {
        switch debt.debtType {
        case "bnpl": return .nexusMood
        case "credit_card": return .nexusPrimary
        case "loan": return .nexusWarning
        case "one_off": return .nexusFinance
        case "family": return .nexusSuccess
        default: return .gray
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        DebtsListView(viewModel: FinanceViewModel())
    }
}
