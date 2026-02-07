import SwiftUI

/// Compact streak badges showing current logging streaks
struct StreakBadgesView: View {
    let streaks: Streaks?

    var body: some View {
        if let streaks = streaks, hasAnyStreak(streaks) {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.xs) {
                HStack(spacing: NexusTheme.Spacing.xs) {
                    ForEach(streaks.sortedStreaks.prefix(4), id: \.name) { item in
                        StreakBadge(
                            name: item.name,
                            icon: item.icon,
                            current: item.data.current,
                            best: item.data.best,
                            isAtBest: item.data.isAtBest
                        )
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

    private func hasAnyStreak(_ streaks: Streaks) -> Bool {
        streaks.water.current > 0 ||
        streaks.meals.current > 0 ||
        streaks.weight.current > 0 ||
        streaks.workout.current > 0
    }
}

/// Individual streak badge
struct StreakBadge: View {
    let name: String
    let icon: String
    let current: Int
    let best: Int
    let isAtBest: Bool

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.xxxs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(badgeColor)

            Text("\(current)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(NexusTheme.Colors.textPrimary)

            if isAtBest && current > 1 {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(NexusTheme.Colors.Semantic.amber)
            }
        }
        .padding(.horizontal, NexusTheme.Spacing.xs)
        .padding(.vertical, NexusTheme.Spacing.xxxs)
        .background(badgeColor.opacity(0.12))
        .cornerRadius(NexusTheme.Radius.xs)
        .accessibilityLabel("\(name): \(current) day streak, best: \(best)")
    }

    private var badgeColor: Color {
        switch name.lowercased() {
        case "weight": return NexusTheme.Colors.Semantic.purple
        case "water": return NexusTheme.Colors.Semantic.blue
        case "meals": return NexusTheme.Colors.Semantic.amber
        case "workout": return NexusTheme.Colors.Semantic.green
        default: return NexusTheme.Colors.textTertiary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Active streaks
        StreakBadgesView(streaks: Streaks(
            water: StreakData(current: 3, best: 5),
            meals: StreakData(current: 7, best: 7),
            weight: StreakData(current: 13, best: 13),
            workout: StreakData(current: 0, best: 2),
            overall: StreakData(current: 3, best: 13),
            computedAt: nil
        ))

        // No active streaks (view should not render)
        StreakBadgesView(streaks: Streaks(
            water: StreakData(current: 0, best: 5),
            meals: StreakData(current: 0, best: 7),
            weight: StreakData(current: 0, best: 13),
            workout: StreakData(current: 0, best: 2),
            overall: StreakData(current: 0, best: 13),
            computedAt: nil
        ))

        // Nil streaks (view should not render)
        StreakBadgesView(streaks: nil)
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
