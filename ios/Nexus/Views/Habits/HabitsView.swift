import SwiftUI

struct HabitsView: View {
    @StateObject private var viewModel = HabitsViewModel()
    @State private var showingAddSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: NexusTheme.Spacing.lg) {
                if viewModel.isLoading && viewModel.habits.isEmpty {
                    ProgressView()
                        .padding(.top, NexusTheme.Spacing.xxxl)
                } else if viewModel.habits.isEmpty {
                    ThemeEmptyState(
                        icon: "checkmark.circle",
                        headline: "No Habits Yet",
                        description: "Start tracking your daily habits to build consistency.",
                        ctaTitle: "Add Habit",
                        ctaAction: { showingAddSheet = true }
                    )
                } else {
                    // Progress header
                    progressHeader

                    // Grouped habits
                    ForEach(viewModel.groupedHabits, id: \.category) { group in
                        habitSection(category: group.category, habits: group.habits)
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                        .padding(.horizontal, NexusTheme.Spacing.md)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.top, NexusTheme.Spacing.md)
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(NexusTheme.Colors.accent)
                }
                .accessibilityLabel("Add habit")
            }
        }
        .refreshable {
            await viewModel.loadHabits()
        }
        .sheet(isPresented: $showingAddSheet) {
            HabitLogSheet { request in
                let success = await viewModel.createHabit(request)
                if success { showingAddSheet = false }
                return success
            }
        }
        .task {
            await viewModel.loadHabits()
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(NexusTheme.Colors.divider, lineWidth: 4)
                    .frame(width: 48, height: 48)

                Circle()
                    .trim(from: 0, to: viewModel.completionProgress)
                    .stroke(
                        viewModel.completionProgress >= 1.0
                            ? NexusTheme.Colors.Semantic.green
                            : NexusTheme.Colors.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.4), value: viewModel.completionProgress)

                Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(NexusTheme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxxs) {
                Text("Today's Progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                if let leader = viewModel.streakLeader {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        Text("\(leader.name) \(leader.currentStreak)d streak")
                            .font(.system(size: 12))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(NexusTheme.Spacing.md)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Section

    private func habitSection(category: String, habits: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
            Text(category.capitalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NexusTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, NexusTheme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(habits) { habit in
                    HabitRow(habit: habit) {
                        Task { await viewModel.completeHabit(id: habit.id) }
                    } onDelete: {
                        Task { await viewModel.deleteHabit(id: habit.id) }
                    }

                    if habit.id != habits.last?.id {
                        Divider()
                            .padding(.leading, 48)
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
}

// MARK: - Habit Row

struct HabitRow: View {
    let habit: Habit
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.sm) {
            // Icon
            Image(systemName: habit.icon ?? "circle")
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 32)

            // Name + streak
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxxs) {
                HStack(spacing: NexusTheme.Spacing.xs) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(NexusTheme.Colors.textPrimary)

                    if habit.currentStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("\(habit.currentStreak)d")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    }
                }

                // 7-day dots
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        Circle()
                            .fill(dotColor(for: i))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Spacer()

            // Complete button
            Button(action: onComplete) {
                Image(systemName: habit.completedToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundColor(habit.completedToday ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.divider)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: habit.completedToday)
            .accessibilityLabel(habit.completedToday ? "Mark \(habit.name) incomplete" : "Complete \(habit.name)")
        }
        .padding(.horizontal, NexusTheme.Spacing.md)
        .padding(.vertical, NexusTheme.Spacing.sm)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        guard index < habit.last7Days.count else {
            return NexusTheme.Colors.divider.opacity(0.5)
        }
        return habit.last7Days[index]
            ? iconColor.opacity(0.8)
            : NexusTheme.Colors.divider.opacity(0.4)
    }

    private var iconColor: Color {
        if let hex = habit.color {
            return Color(hex: hex)
        }
        switch habit.category {
        case "health": return NexusTheme.Colors.Semantic.blue
        case "fitness": return NexusTheme.Colors.Semantic.red
        case "productivity": return NexusTheme.Colors.Semantic.amber
        case "mindfulness": return NexusTheme.Colors.Semantic.purple
        default: return NexusTheme.Colors.accent
        }
    }
}


#Preview {
    NavigationStack {
        HabitsView()
    }
}
