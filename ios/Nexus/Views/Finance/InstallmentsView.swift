import SwiftUI

struct InstallmentsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var installments: [InstallmentPlan] = []
    @State private var summary: InstallmentsSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading installments...")
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    errorView(error)
                } else if installments.isEmpty {
                    emptyStateView
                } else {
                    if let summary = summary {
                        summaryCard(summary)
                    }
                    installmentsList
                }
            }
            .padding()
        }
        .refreshable {
            await loadInstallments()
        }
        .task {
            await loadInstallments()
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: InstallmentsSummary) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(installments.first?.currency ?? "AED") \(summary.totalRemaining)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Spacer()
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 32))
                    .foregroundColor(.nexusMood.opacity(0.7))
            }

            Divider()

            HStack(spacing: 24) {
                statItem(
                    icon: "list.bullet.rectangle",
                    value: "\(summary.activePlans)",
                    label: "Active Plans"
                )

                if summary.dueThisWeek > 0 {
                    statItem(
                        icon: "calendar.badge.exclamationmark",
                        value: "\(summary.dueThisWeek)",
                        label: "Due This Week",
                        isWarning: true
                    )
                }
            }

            if summary.dueThisWeek > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.nexusWarning)
                    Text("\(installments.first?.currency ?? "AED") \(summary.dueThisWeekAmount) due this week")
                        .font(.subheadline)
                        .foregroundColor(.nexusWarning)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.nexusWarning.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    private func statItem(icon: String, value: String, label: String, isWarning: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isWarning ? .nexusWarning : .nexusMood)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(isWarning ? .nexusWarning : .primary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Installments List

    private var installmentsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Plans")
                .font(.headline)
                .foregroundColor(.secondary)

            ForEach(installments) { plan in
                installmentRow(plan)
            }
        }
    }

    private func installmentRow(_ plan: InstallmentPlan) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Source icon
                ZStack {
                    Circle()
                        .fill(sourceColor(plan.source).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: plan.sourceIcon)
                        .font(.system(size: 18))
                        .foregroundColor(sourceColor(plan.source))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(plan.merchant)
                            .font(.headline)
                        Spacer()
                        Text("\(plan.currency) \(String(format: "%.2f", plan.totalAmount))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(plan.source.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(sourceColor(plan.source).opacity(0.15))
                            .foregroundColor(sourceColor(plan.source))
                            .cornerRadius(4)

                        Text(plan.progress)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if plan.isOverdue {
                            Text("OVERDUE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.nexusError)
                                .cornerRadius(4)
                        } else if plan.isDueSoon {
                            Text("DUE SOON")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.nexusWarning)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding()

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    Rectangle()
                        .fill(sourceColor(plan.source))
                        .frame(width: geometry.size.width * progressPercent(plan), height: 4)
                }
            }
            .frame(height: 4)

            // Next payment info
            if let nextDue = plan.nextDueDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Next: \(plan.currency) \(String(format: "%.2f", plan.installmentAmount)) on \(formatDate(nextDue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(plan.remainingPayments) left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
            }
        }
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.nexusSuccess)

            Text("No Active Installments")
                .font(.headline)

            Text("Your BNPL purchases from Tabby, Tamara, and others will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.nexusWarning)

            Text("Could not load installments")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await loadInstallments()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func sourceColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "tabby": return .nexusMood
        case "tamara": return .nexusWater
        case "postpay": return .nexusSuccess
        default: return .gray
        }
    }

    private func progressPercent(_ plan: InstallmentPlan) -> Double {
        guard plan.installmentsTotal > 0 else { return 0 }
        return Double(plan.installmentsPaid) / Double(plan.installmentsTotal)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadInstallments() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchInstallments()
            await MainActor.run {
                self.installments = response.plans
                self.summary = response.summary
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

#Preview {
    InstallmentsView(viewModel: FinanceViewModel())
}
