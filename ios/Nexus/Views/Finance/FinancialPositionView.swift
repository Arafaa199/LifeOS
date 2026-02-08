import SwiftUI
import UIKit
import Combine

/// Comprehensive financial position view showing accounts, balances, and upcoming obligations
struct FinancialPositionView: View {
    @StateObject private var viewModel = FinancialPositionViewModel()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ScrollView {
            VStack(spacing: NexusTheme.Spacing.lg) {
                if viewModel.isLoading && viewModel.position == nil {
                    ProgressView("Loading financial position...")
                        .padding(.top, 60)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if let position = viewModel.position {
                    // Net Worth Summary
                    netWorthCard(position.summary)

                    // Accounts Section
                    if let accounts = position.accounts, !accounts.isEmpty {
                        accountsSection(accounts)
                    }

                    // Upcoming Payments Section
                    if let payments = position.upcomingPayments, !payments.isEmpty {
                        upcomingPaymentsSection(payments)
                    }

                    // Monthly Obligations
                    if let obligations = position.monthlyObligations {
                        monthlyObligationsCard(obligations)
                    }
                }
            }
            .padding()
        }
        .background(NexusTheme.Colors.background)
        .refreshable {
            haptics.impactOccurred()
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .navigationTitle("Financial Position")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Net Worth Card

    private func netWorthCard(_ summary: FinancialSummary) -> some View {
        VStack(spacing: NexusTheme.Spacing.md) {
            // Net Worth Hero
            VStack(spacing: NexusTheme.Spacing.xs) {
                Text("Net Worth")
                    .font(.subheadline)
                    .foregroundColor(NexusTheme.Colors.textSecondary)

                Text(formatCurrency(summary.netWorth, currency: summary.currency))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(summary.netWorth >= 0 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NexusTheme.Spacing.lg)

            Divider()

            // Assets vs Liabilities
            HStack(spacing: NexusTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxs) {
                    Text("Assets")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(summary.totalAssets, currency: summary.currency))
                        .font(.headline)
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: NexusTheme.Spacing.xxs) {
                    Text("Liabilities")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(summary.totalLiabilities, currency: summary.currency))
                        .font(.headline)
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                }
            }

            Divider()

            // Available after bills
            HStack {
                VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxs) {
                    Text("After Upcoming Bills")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(summary.availableAfterBills, currency: summary.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(summary.availableAfterBills >= 0 ? NexusTheme.Colors.textPrimary : NexusTheme.Colors.Semantic.red)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: NexusTheme.Spacing.xxs) {
                    Text("Due in 30 Days")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(summary.upcoming30d, currency: summary.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
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

    // MARK: - Accounts Section

    private func accountsSection(_ accounts: [AccountBalance]) -> some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
            Text("Accounts")
                .font(.headline)
                .foregroundColor(NexusTheme.Colors.textPrimary)
                .padding(.horizontal, NexusTheme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    accountRow(account)
                    if index < accounts.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
    }

    private func accountRow(_ account: AccountBalance) -> some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(accountColor(account).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: accountIcon(account))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accountColor(account))
            }

            // Name and institution
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                if let institution = account.institution {
                    Text(institution)
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
            }

            Spacer()

            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(account.balance, currency: account.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(account.isLiability ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.textPrimary)

                if account.isLiability, let _ = account.creditLimit, let available = account.availableCredit {
                    Text("\(formatCurrency(available, currency: account.currency)) available")
                        .font(.caption2)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
            }
        }
        .padding(NexusTheme.Spacing.md)
    }

    private func accountIcon(_ account: AccountBalance) -> String {
        if account.isLiability {
            return "creditcard.fill"
        }
        switch account.type?.lowercased() {
        case "savings": return "banknote.fill"
        case "checking": return "building.columns.fill"
        default: return "dollarsign.circle.fill"
        }
    }

    private func accountColor(_ account: AccountBalance) -> Color {
        if account.isLiability {
            return NexusTheme.Colors.accent
        }
        return NexusTheme.Colors.Semantic.green
    }

    // MARK: - Upcoming Payments Section

    private func upcomingPaymentsSection(_ payments: [UpcomingPayment]) -> some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
            HStack {
                Text("Upcoming Payments")
                    .font(.headline)
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                Spacer()

                let overdueCount = payments.filter { $0.isOverdue }.count
                let dueSoonCount = payments.filter { $0.isDueSoon }.count

                if overdueCount > 0 {
                    Text("\(overdueCount) overdue")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NexusTheme.Colors.Semantic.red)
                        .cornerRadius(NexusTheme.Radius.sm)
                } else if dueSoonCount > 0 {
                    Text("\(dueSoonCount) due soon")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NexusTheme.Colors.Semantic.amber)
                        .cornerRadius(NexusTheme.Radius.sm)
                }
            }
            .padding(.horizontal, NexusTheme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(payments.prefix(10).enumerated()), id: \.element.id) { index, payment in
                    paymentRow(payment)
                    if index < min(payments.count - 1, 9) {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
    }

    private func paymentRow(_ payment: UpcomingPayment) -> some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(paymentColor(payment).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: paymentIcon(payment))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(paymentColor(payment))
            }

            // Name and due date
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let dueDate = payment.dueDateFormatted {
                        Text(dueDate)
                            .font(.caption)
                            .foregroundColor(paymentColor(payment))
                    }

                    if let remaining = payment.installmentsRemaining, remaining > 0 {
                        Text("• \(remaining) left")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.textMuted)
                    }
                }
            }

            Spacer()

            // Amount and urgency
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(payment.amount, currency: payment.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NexusTheme.Colors.Semantic.red)

                if payment.isOverdue {
                    Text("OVERDUE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NexusTheme.Colors.Semantic.red)
                        .cornerRadius(4)
                } else if let days = payment.daysUntilDue {
                    Text(daysUntilText(days))
                        .font(.caption2)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
            }
        }
        .padding(NexusTheme.Spacing.md)
    }

    private func paymentIcon(_ payment: UpcomingPayment) -> String {
        if payment.type == "installment" {
            return "creditcard.and.123"
        }
        return "repeat.circle.fill"
    }

    private func paymentColor(_ payment: UpcomingPayment) -> Color {
        if payment.isOverdue {
            return NexusTheme.Colors.Semantic.red
        } else if payment.isDueSoon {
            return NexusTheme.Colors.Semantic.amber
        }
        return NexusTheme.Colors.Semantic.blue
    }

    private func daysUntilText(_ days: Int) -> String {
        if days == 0 { return "Due today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }

    // MARK: - Monthly Obligations Card

    private func monthlyObligationsCard(_ obligations: MonthlyObligations) -> some View {
        VStack(spacing: NexusTheme.Spacing.md) {
            HStack {
                Text("Monthly Obligations")
                    .font(.headline)
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                Spacer()
                Text(formatCurrency(obligations.total, currency: AppSettings.shared.defaultCurrency))
                    .font(.title3.weight(.bold))
                    .foregroundColor(NexusTheme.Colors.Semantic.red)
            }

            Divider()

            HStack(spacing: NexusTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxs) {
                    Text("Recurring")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(obligations.recurringTotal, currency: AppSettings.shared.defaultCurrency))
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: NexusTheme.Spacing.xxs) {
                    Text("Installments")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)
                    Text(formatCurrency(obligations.installmentsTotal, currency: AppSettings.shared.defaultCurrency))
                        .font(.subheadline.weight(.medium))
                }
            }

            Text("\(obligations.count) payments this month")
                .font(.caption)
                .foregroundColor(NexusTheme.Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: NexusTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(NexusTheme.Colors.Semantic.amber)

            Text("Could not load financial position")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundColor(NexusTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                haptics.impactOccurred()
                Task { await viewModel.load() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }
}

#Preview {
    NavigationView {
        FinancialPositionView()
    }
}
