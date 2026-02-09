import SwiftUI

/// Recovery ring with score, sleep duration, composition breakdown, and sync freshness
struct RecoveryCardView: View {
    let recoveryScore: Int?
    let sleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let sleepEfficiency: Double?
    let healthStatus: String?
    let freshness: DomainFreshness?

    // Trend indicators
    let recoveryVs7d: Double?
    let sleepVs7d: Double?
    let recoveryUnusual: Bool?
    let sleepUnusual: Bool?

    // Computed light sleep
    private var lightSleepMinutes: Int? {
        guard let total = sleepMinutes, let deep = deepSleepMinutes, let rem = remSleepMinutes else {
            return nil
        }
        return max(0, total - deep - rem)
    }

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Recovery ring
            ZStack {
                Circle()
                    .stroke(NexusTheme.Colors.divider, lineWidth: 6)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: recoveryProgress)
                    .stroke(recoveryColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: recoveryProgress)

                Text(recoveryText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(recoveryColor)
            }
            .accessibilityLabel("Recovery \(recoveryText)")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Recovery")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(NexusTheme.Colors.textPrimary)

                    // Recovery trend indicator
                    if let vs7d = recoveryVs7d, recoveryScore != nil {
                        trendIndicator(vs7d: vs7d, isUnusual: recoveryUnusual ?? false)
                    }

                    // Sleep efficiency badge
                    if let efficiency = sleepEfficiency {
                        Text("\(Int(efficiency * 100))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(efficiencyColor(efficiency))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(efficiencyColor(efficiency).opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                if recoveryScore == nil {
                    if healthStatus == "healthy" || healthStatus == nil {
                        Text("Pending...")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                    } else {
                        Text("Unavailable")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                    }
                }

                if let sleep = sleepMinutes {
                    HStack(spacing: 3) {
                        Text(formatSleep(sleep))
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)

                        // Sleep trend indicator
                        if let vs7d = sleepVs7d {
                            trendIndicator(vs7d: vs7d, isUnusual: sleepUnusual ?? false)
                        }
                    }
                }

                // Sleep composition breakdown
                if let deep = deepSleepMinutes, let rem = remSleepMinutes, let light = lightSleepMinutes, let total = sleepMinutes, total > 0 {
                    sleepCompositionView(deep: deep, rem: rem, light: light, total: total)
                }

                if let freshness {
                    Text(freshness.syncTimeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(freshness.isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - Sleep Composition

    @ViewBuilder
    private func sleepCompositionView(deep: Int, rem: Int, light: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Horizontal composition bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    Rectangle()
                        .fill(NexusTheme.Colors.Semantic.purple)
                        .frame(width: geo.size.width * CGFloat(deep) / CGFloat(total))
                    Rectangle()
                        .fill(NexusTheme.Colors.Semantic.blue)
                        .frame(width: geo.size.width * CGFloat(rem) / CGFloat(total))
                    Rectangle()
                        .fill(NexusTheme.Colors.textTertiary.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(light) / CGFloat(total))
                }
                .cornerRadius(2)
            }
            .frame(height: 4)

            // Stat pills
            HStack(spacing: 4) {
                sleepPill(label: "Deep", minutes: deep, color: NexusTheme.Colors.Semantic.purple)
                sleepPill(label: "REM", minutes: rem, color: NexusTheme.Colors.Semantic.blue)
                sleepPill(label: "Light", minutes: light, color: NexusTheme.Colors.textTertiary)
            }
        }
    }

    private func sleepPill(label: String, minutes: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(minutes / 60)h\(minutes % 60 > 0 ? "\(minutes % 60)m" : "")")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textTertiary)
        }
    }

    private func efficiencyColor(_ efficiency: Double) -> Color {
        switch efficiency {
        case 0.85...: return NexusTheme.Colors.Semantic.green
        case 0.70..<0.85: return NexusTheme.Colors.Semantic.amber
        default: return NexusTheme.Colors.Semantic.red
        }
    }

    // MARK: - Trend Indicator

    private func trendIndicator(vs7d: Double, isUnusual: Bool) -> some View {
        let arrow: String
        if vs7d > 5 { arrow = "↑" }
        else if vs7d < -5 { arrow = "↓" }
        else { arrow = "→" }

        let color: Color = isUnusual ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.textTertiary

        return Text(arrow)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
    }

    // MARK: - Computed Properties

    private var recoveryProgress: CGFloat {
        guard let score = recoveryScore else { return 0 }
        return CGFloat(score) / 100.0
    }

    private var recoveryText: String {
        guard let score = recoveryScore else {
            if healthStatus == "healthy" || healthStatus == nil {
                return "..."
            }
            return "--"
        }
        return "\(score)%"
    }

    private var recoveryColor: Color {
        guard let score = recoveryScore else {
            if healthStatus == "healthy" || healthStatus == nil {
                return NexusTheme.Colors.textTertiary
            }
            return NexusTheme.Colors.textMuted
        }
        switch score {
        case 67...100: return NexusTheme.Colors.Semantic.green
        case 34...66: return NexusTheme.Colors.Semantic.amber
        default: return NexusTheme.Colors.Semantic.red
        }
    }

    // MARK: - Helpers

    private func formatSleep(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m sleep"
        } else if hours > 0 {
            return "\(hours)h sleep"
        }
        return "\(mins)m sleep"
    }
}

#Preview {
    VStack(spacing: 20) {
        // With sleep composition and trends
        RecoveryCardView(
            recoveryScore: 72,
            sleepMinutes: 420,
            deepSleepMinutes: 90,
            remSleepMinutes: 105,
            sleepEfficiency: 0.92,
            healthStatus: "healthy",
            freshness: nil,
            recoveryVs7d: 12.5,
            sleepVs7d: -8.0,
            recoveryUnusual: false,
            sleepUnusual: true
        )

        // Without trends (nil values)
        RecoveryCardView(
            recoveryScore: 65,
            sleepMinutes: 380,
            deepSleepMinutes: nil,
            remSleepMinutes: nil,
            sleepEfficiency: nil,
            healthStatus: "healthy",
            freshness: nil,
            recoveryVs7d: nil,
            sleepVs7d: nil,
            recoveryUnusual: nil,
            sleepUnusual: nil
        )
    }
    .padding()
    .background(NexusTheme.Colors.card)
}
