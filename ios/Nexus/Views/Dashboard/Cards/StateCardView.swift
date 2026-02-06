import SwiftUI

/// Combined state card showing recovery, budget, workouts, and reminders
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

    // Workout data
    let workoutCount: Int?
    let workoutMinutes: Int?

    // Reminder data
    let reminderSummary: ReminderSummary?

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                RecoveryCardView(
                    recoveryScore: recoveryScore,
                    sleepMinutes: sleepMinutes,
                    healthStatus: healthStatus,
                    freshness: healthFreshness
                )

                Spacer(minLength: 12)

                Divider()
                    .frame(height: 50)
                    .padding(.horizontal, 4)

                Spacer(minLength: 12)

                BudgetCardView(
                    spendTotal: spendTotal,
                    spendVs7d: spendVs7d,
                    spendUnusual: spendUnusual,
                    freshness: financeFreshness,
                    hasData: hasData,
                    currency: currency
                )
            }

            // Workout row (only show if there are workouts)
            if let count = workoutCount, count > 0 {
                Divider()
                workoutRow(count: count, minutes: workoutMinutes ?? 0)
            }

            if let reminders = reminderSummary,
               reminders.dueToday > 0 || reminders.overdueCount > 0 {
                Divider()
                reminderRow(reminders)
            }
        }
        .padding(20)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    private func workoutRow(count: Int, minutes: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.run")
                .font(.caption)
                .foregroundColor(.nexusSuccess)

            Text("\(count) workout\(count == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            Text("\u{00B7}")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(minutes) min")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private func reminderRow(_ reminders: ReminderSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.caption)
                .foregroundColor(reminders.overdueCount > 0 ? .nexusError : .secondary)

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
                    .foregroundColor(.nexusError)
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
        workoutCount: 1,
        workoutMinutes: 45,
        reminderSummary: nil
    )
    .padding()
}
