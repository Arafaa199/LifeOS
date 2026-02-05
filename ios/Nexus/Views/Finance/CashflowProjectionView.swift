import SwiftUI

struct CashflowProjectionView: View {
    @ObservedObject var viewModel: FinanceViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.cashflowProjection.isEmpty {
                    emptyState
                } else {
                    summaryHeader
                    ForEach(viewModel.cashflowProjection) { month in
                        monthCard(month)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Cashflow Projection")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.loadCashflowProjection()
        }
        .onAppear {
            viewModel.loadCashflowProjection()
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            if let debtFreeMonth = debtFreeMonth {
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(.nexusSuccess)
                    Text("Debt-free by: \(debtFreeMonth)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.nexusSuccess)
                    Spacer()
                }
                .padding()
                .background(Color.nexusSuccess.opacity(0.1))
                .cornerRadius(12)
            }

            if let last = viewModel.cashflowProjection.last {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("Projected Savings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(last.cumulativeSavings, currency: AppSettings.shared.defaultCurrency))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(last.cumulativeSavings >= 0 ? .nexusSuccess : .nexusError)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Debt Remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(last.activeDebtsRemaining, currency: AppSettings.shared.defaultCurrency))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(last.activeDebtsRemaining > 0 ? .nexusWarning : .nexusSuccess)
                    }
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Month Card

    private func monthCard(_ month: CashflowMonth) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(month.monthLabel)
                    .font(.headline)
                Spacer()
                Text(formatCurrency(month.projectedNet, currency: AppSettings.shared.defaultCurrency))
                    .font(.headline)
                    .foregroundColor(month.isPositiveNet ? .nexusSuccess : .nexusError)
            }
            .padding()

            Divider()

            VStack(spacing: 8) {
                cashflowRow("Income", amount: month.projectedIncome, color: .nexusSuccess, icon: "arrow.down.circle.fill")
                cashflowRow("Fixed Expenses", amount: month.projectedFixedExpenses, color: .nexusWarning, icon: "arrow.up.circle.fill")
                cashflowRow("Debt Payments", amount: month.projectedDebtPayments, color: .nexusError, icon: "creditcard.fill")

                Divider()

                HStack {
                    Text("Cumulative")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatCurrency(month.cumulativeSavings, currency: AppSettings.shared.defaultCurrency))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(month.cumulativeSavings >= 0 ? .nexusSuccess : .nexusError)
                }

                if month.activeDebtsRemaining > 0 {
                    HStack {
                        Text("Debts remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatCurrency(month.activeDebtsRemaining, currency: AppSettings.shared.defaultCurrency))
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                }
            }
            .padding()
        }
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(month.isPositiveNet ? Color.nexusSuccess.opacity(0.3) : Color.nexusError.opacity(0.3), lineWidth: 1)
        )
    }

    private func cashflowRow(_ label: String, amount: Double, color: Color, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(formatCurrency(amount, currency: AppSettings.shared.defaultCurrency))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Projection Data")
                .font(.headline)
            Text("Set up recurring items and debts to see your cashflow projection.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private var debtFreeMonth: String? {
        guard let first = viewModel.cashflowProjection.first,
              first.activeDebtsRemaining > 0 else { return nil }

        if let month = viewModel.cashflowProjection.first(where: { $0.activeDebtsRemaining == 0 }) {
            return month.monthLabel
        }
        return nil
    }
}

#Preview {
    NavigationView {
        CashflowProjectionView(viewModel: FinanceViewModel())
    }
}
