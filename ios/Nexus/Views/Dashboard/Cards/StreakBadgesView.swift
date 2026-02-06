import SwiftUI

/// Compact streak badges showing current logging streaks
struct StreakBadgesView: View {
    let streaks: Streaks?

    var body: some View {
        if let streaks = streaks, hasAnyStreak(streaks) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
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
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(badgeColor)

            Text("\(current)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.primary)

            if isAtBest && current > 1 {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(6)
        .help("\(name): \(current) day streak (best: \(best))")
    }

    private var badgeColor: Color {
        switch name.lowercased() {
        case "weight": return .purple
        case "water": return .blue
        case "meals": return .orange
        case "workout": return .green
        default: return .gray
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
    .background(Color(UIColor.systemGroupedBackground))
}
