import SwiftUI

struct HabitsCardView: View {
    let habits: [Habit]?
    let onComplete: (Int) -> Void

    var body: some View {
        if let habits = habits, !habits.isEmpty {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
                // Header: progress + streak leader
                HStack {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.accent)

                        Text("Habits")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                    }

                    Spacer()

                    // Completion count
                    let completed = habits.filter(\.completedToday).count
                    Text("\(completed)/\(habits.count)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundColor(completed == habits.count
                            ? NexusTheme.Colors.Semantic.green
                            : NexusTheme.Colors.textSecondary)
                }

                // Incomplete habits (max 4)
                let incomplete = habits.filter { !$0.completedToday }.prefix(4)
                if incomplete.isEmpty {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                        Text("All habits completed!")
                            .font(.system(size: 13))
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                    }
                } else {
                    ForEach(Array(incomplete)) { habit in
                        HStack(spacing: NexusTheme.Spacing.sm) {
                            Image(systemName: habit.icon ?? "circle")
                                .font(.system(size: 13))
                                .foregroundColor(habitColor(habit))
                                .frame(width: 20)

                            Text(habit.name)
                                .font(.system(size: 13))
                                .foregroundColor(NexusTheme.Colors.textSecondary)

                            if habit.currentStreak > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 9))
                                    Text("\(habit.currentStreak)d")
                                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                }
                                .foregroundColor(NexusTheme.Colors.Semantic.amber)
                            }

                            Spacer()

                            Button {
                                onComplete(habit.id)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(NexusTheme.Colors.divider)
                            }
                        }
                    }
                }

                // Streak leader
                if let leader = habits.filter({ $0.currentStreak > 0 }).max(by: { $0.currentStreak < $1.currentStreak }),
                   leader.currentStreak >= 3 {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        Text("\(leader.name): \(leader.currentStreak)-day streak")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                    }
                }
            }
            .padding(NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
    }

    private func habitColor(_ habit: Habit) -> Color {
        if let hex = habit.color {
            return Color(hex: hex)
        }
        return NexusTheme.Colors.accent
    }
}
