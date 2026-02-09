import SwiftUI

/// Combined state card showing recovery, budget, workouts, and reminders
struct StateCardView: View {
    // Recovery data
    let recoveryScore: Int?
    let sleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let sleepEfficiency: Double?
    let healthStatus: String?
    let healthFreshness: DomainFreshness?

    // Trend indicators
    let recoveryVs7d: Double?
    let sleepVs7d: Double?
    let recoveryUnusual: Bool?
    let sleepUnusual: Bool?

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
        VStack(spacing: NexusTheme.Spacing.md) {
            HStack(spacing: 0) {
                RecoveryCardView(
                    recoveryScore: recoveryScore,
                    sleepMinutes: sleepMinutes,
                    deepSleepMinutes: deepSleepMinutes,
                    remSleepMinutes: remSleepMinutes,
                    sleepEfficiency: sleepEfficiency,
                    healthStatus: healthStatus,
                    freshness: healthFreshness,
                    recoveryVs7d: recoveryVs7d,
                    sleepVs7d: sleepVs7d,
                    recoveryUnusual: recoveryUnusual,
                    sleepUnusual: sleepUnusual
                )

                Spacer(minLength: NexusTheme.Spacing.md)

                Rectangle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(width: 1, height: 50)

                Spacer(minLength: NexusTheme.Spacing.md)

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
                Rectangle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(height: 1)
                workoutRow(count: count, minutes: workoutMinutes ?? 0)
            }

            if let reminders = reminderSummary,
               reminders.dueToday > 0 || reminders.overdueCount > 0 {
                Rectangle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(height: 1)
                reminderRow(reminders)
            }
        }
        .padding(NexusTheme.Spacing.xxl)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    private func workoutRow(count: Int, minutes: Int) -> some View {
        HStack(spacing: NexusTheme.Spacing.xxs) {
            Image(systemName: "figure.run")
                .font(.system(size: 11))
                .foregroundColor(NexusTheme.Colors.Semantic.green)

            Text("\(count) workout\(count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textSecondary)

            Text("\u{00B7}")
                .font(.system(size: 11))
                .foregroundColor(NexusTheme.Colors.textTertiary)

            Text("\(minutes) min")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textSecondary)

            Spacer()
        }
    }

    private func reminderRow(_ reminders: ReminderSummary) -> some View {
        HStack(spacing: NexusTheme.Spacing.xxs) {
            Image(systemName: "bell.fill")
                .font(.system(size: 11))
                .foregroundColor(reminders.overdueCount > 0 ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.textTertiary)

            if reminders.dueToday > 0 {
                Text("\(reminders.dueToday) due today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textSecondary)
            }

            if reminders.dueToday > 0 && reminders.overdueCount > 0 {
                Text("\u{00B7}")
                    .font(.system(size: 11))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }

            if reminders.overdueCount > 0 {
                Text("\(reminders.overdueCount) overdue")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.Semantic.red)
            }

            Spacer()
        }
    }
}

#Preview {
    StateCardView(
        recoveryScore: 72,
        sleepMinutes: 420,
        deepSleepMinutes: 90,
        remSleepMinutes: 105,
        sleepEfficiency: 0.92,
        healthStatus: "healthy",
        healthFreshness: nil,
        recoveryVs7d: 12.5,
        sleepVs7d: -8.0,
        recoveryUnusual: false,
        sleepUnusual: true,
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
    .background(NexusTheme.Colors.background)
}
