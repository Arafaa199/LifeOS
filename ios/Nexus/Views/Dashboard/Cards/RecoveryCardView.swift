import SwiftUI

/// Recovery ring with score, sleep duration, and sync freshness
struct RecoveryCardView: View {
    let recoveryScore: Int?
    let sleepMinutes: Int?
    let healthStatus: String?
    let freshness: DomainFreshness?

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
                Text("Recovery")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

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
                    Text(formatSleep(sleep))
                        .font(.system(size: 11))
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                }

                if let freshness {
                    Text(freshness.syncTimeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(freshness.isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.textTertiary)
                }
            }
        }
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
    RecoveryCardView(
        recoveryScore: 72,
        sleepMinutes: 420,
        healthStatus: "healthy",
        freshness: nil
    )
    .padding()
    .background(NexusTheme.Colors.card)
}
