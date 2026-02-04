import SwiftUI

/// Combined state card showing recovery, budget, and reminders
struct StateCardView: View {
    // Recovery data
    let recoveryScore: Int?
    let sleepMinutes: Int?
    let healthStatus: String?
    let healthFreshness: DomainFreshness?

    // Budget data
    let spendTotal: Double?
    let spendVs7d: Double?
    let spendUnusual: Bool?
    let financeFreshness: DomainFreshness?
    let hasData: Bool
    let currency: String

    // Reminder data
    let reminderSummary: ReminderSummary?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                RecoveryCardView(
                    recoveryScore: recoveryScore,
                    sleepMinutes: sleepMinutes,
                    healthStatus: healthStatus,
                    freshness: healthFreshness
                )
                Spacer()
                BudgetCardView(
                    spendTotal: spendTotal,
                    spendVs7d: spendVs7d,
                    spendUnusual: spendUnusual,
                    freshness: financeFreshness,
                    hasData: hasData,
                    currency: currency
                )
            }

            if let reminders = reminderSummary,
               reminders.dueToday > 0 || reminders.overdueCount > 0 {
                reminderRow(reminders)
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func reminderRow(_ reminders: ReminderSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.caption)
                .foregroundColor(reminders.overdueCount > 0 ? .red : .secondary)

            if reminders.dueToday > 0 {
                Text("\(reminders.dueToday) due today")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }

            if reminders.dueToday > 0 && reminders.overdueCount > 0 {
                Text("\u{00B7}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if reminders.overdueCount > 0 {
                Text("\(reminders.overdueCount) overdue")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.red)
            }

            Spacer()
        }
    }
}

#Preview {
    StateCardView(
        recoveryScore: 72,
        sleepMinutes: 420,
        healthStatus: "healthy",
        healthFreshness: nil,
        spendTotal: 150.0,
        spendVs7d: 25.0,
        spendUnusual: false,
        financeFreshness: nil,
        hasData: true,
        currency: "AED",
        reminderSummary: nil
    )
    .padding()
}
