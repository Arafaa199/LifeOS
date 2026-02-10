import SwiftUI
import Combine

/// Compact financial position card for the dashboard
/// Shows net worth and upcoming bills at a glance
struct FinanceQuickCard: View {
    @StateObject private var viewModel = FinanceQuickViewModel()

    var body: some View {
        NavigationLink(destination: FinancialPositionView()) {
            HStack(spacing: NexusTheme.Spacing.lg) {
                // Net Worth
                VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxs) {
                    Text("Net Worth")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textMuted)

                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let netWorth = viewModel.netWorth {
                        Text(formatCurrency(netWorth, currency: "AED"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(netWorth >= 0 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.red)
                    } else {
                        Text("--")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
                }

                Spacer()

                // Divider
                Rectangle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(width: 1, height: 36)

                Spacer()

                // Due This Week
                VStack(alignment: .trailing, spacing: NexusTheme.Spacing.xxs) {
                    HStack(spacing: 4) {
                        if viewModel.dueThisWeekCount > 0 {
                            Text("\(viewModel.dueThisWeekCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(viewModel.hasOverdue ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.amber)
                                .cornerRadius(8)
                        }
                        Text("Due This Week")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.textMuted)
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(formatCurrency(viewModel.dueThisWeekAmount, currency: "AED"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(viewModel.dueThisWeekAmount > 0 ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.textSecondary)
                    }
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.textMuted)
            }
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - View Model

@MainActor
class FinanceQuickViewModel: ObservableObject {
    @Published var netWorth: Double?
    @Published var dueThisWeekAmount: Double = 0
    @Published var dueThisWeekCount: Int = 0
    @Published var hasOverdue: Bool = false
    @Published var isLoading = false

    private let api = FinanceAPI.shared

    func load() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            let response = try await api.fetchFinancialPosition()
            if response.success {
                netWorth = response.summary.netWorth

                // Calculate due this week
                if let payments = response.upcomingPayments {
                    let thisWeek = payments.filter { ($0.daysUntilDue ?? 999) <= 7 }
                    dueThisWeekCount = thisWeek.count
                    dueThisWeekAmount = thisWeek.reduce(0) { sum, payment in
                        let amount = payment.currency == "SAR" ? payment.amount * 0.98 : payment.amount
                        return sum + amount
                    }
                    hasOverdue = thisWeek.contains { $0.isOverdue }
                }
            }
        } catch {
            // Silent fail - card just shows "--"
        }

        isLoading = false
    }
}

#Preview {
    VStack {
        FinanceQuickCard()
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
