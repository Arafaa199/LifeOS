import SwiftUI

/// Recovery ring with score, sleep duration, and sync freshness
struct RecoveryCardView: View {
    let recoveryScore: Int?
    let sleepMinutes: Int?
    let healthStatus: String?
    let freshness: DomainFreshness?

    var body: some View {
        HStack(spacing: 12) {
            // Recovery ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 6)
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
                    .font(.subheadline.weight(.medium))

                if recoveryScore == nil {
                    if healthStatus == "healthy" || healthStatus == nil {
                        Text("Pending...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let sleep = sleepMinutes {
                    Text(formatSleep(sleep))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let freshness {
                    Text(freshness.syncTimeLabel)
                        .font(.caption2)
                        .foregroundColor(freshness.isStale ? .nexusWarning : .secondary)
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
                return .secondary
            }
            return .gray
        }
        switch score {
        case 67...100: return .nexusSuccess
        case 34...66: return .nexusWarning
        default: return .nexusError
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
}
