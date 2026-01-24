import SwiftUI

// MARK: - WHOOP Recovery Metrics Row

struct WHOOPRecoveryRow: View {
    let recovery: RecoveryMetrics?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let recovery = recovery {
                if let score = recovery.recoveryScore {
                    HealthMetricCard(
                        title: "Recovery",
                        value: "\(score)",
                        unit: "%",
                        icon: "heart.circle.fill",
                        color: recoveryColor(score),
                        isLoading: isLoading
                    )
                }

                if let hrv = recovery.hrv {
                    HealthMetricCard(
                        title: "HRV",
                        value: String(format: "%.0f", hrv),
                        unit: "ms",
                        icon: "waveform.path.ecg",
                        color: .purple,
                        isLoading: isLoading
                    )
                }

                if let rhr = recovery.rhr {
                    HealthMetricCard(
                        title: "Resting HR",
                        value: "\(rhr)",
                        unit: "bpm",
                        icon: "heart.fill",
                        color: .red,
                        isLoading: isLoading
                    )
                }
            } else if isLoading {
                // Placeholder cards while loading
                HealthMetricCard(title: "Recovery", value: "--", unit: "%", icon: "heart.circle.fill", color: .gray, isLoading: true)
                HealthMetricCard(title: "HRV", value: "--", unit: "ms", icon: "waveform.path.ecg", color: .gray, isLoading: true)
                HealthMetricCard(title: "Resting HR", value: "--", unit: "bpm", icon: "heart.fill", color: .gray, isLoading: true)
            }
        }
    }

    private func recoveryColor(_ score: Int) -> Color {
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }
}

// MARK: - WHOOP Sleep Metrics Row

struct WHOOPSleepRow: View {
    let sleep: SleepMetrics?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let sleep = sleep {
                if sleep.totalSleepMin > 0 {
                    HealthMetricCard(
                        title: "Sleep",
                        value: formatDuration(sleep.totalSleepMin),
                        unit: "",
                        icon: "bed.double.fill",
                        color: .indigo,
                        isLoading: isLoading
                    )
                }

                if let deep = sleep.deepSleepMin, deep > 0 {
                    HealthMetricCard(
                        title: "Deep",
                        value: formatDuration(deep),
                        unit: "",
                        icon: "moon.zzz.fill",
                        color: .blue,
                        isLoading: isLoading
                    )
                }

                if let perf = sleep.sleepPerformance {
                    HealthMetricCard(
                        title: "Sleep Score",
                        value: "\(perf)",
                        unit: "%",
                        icon: "sparkles",
                        color: .cyan,
                        isLoading: isLoading
                    )
                }
            } else if isLoading {
                // Placeholder cards while loading
                HealthMetricCard(title: "Sleep", value: "--", unit: "", icon: "bed.double.fill", color: .gray, isLoading: true)
                HealthMetricCard(title: "Deep", value: "--", unit: "", icon: "moon.zzz.fill", color: .gray, isLoading: true)
                HealthMetricCard(title: "Sleep Score", value: "--", unit: "%", icon: "sparkles", color: .gray, isLoading: true)
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}

// MARK: - WHOOP Error State

struct WHOOPErrorView: View {
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load WHOOP data")
                    .font(.subheadline.weight(.medium))
                Text(errorMessage ?? "Unknown error")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.nexusPrimary)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview("Recovery Row - Loading") {
    WHOOPRecoveryRow(
        recovery: nil,
        isLoading: true
    )
    .padding()
}

#Preview("Sleep Row - Loading") {
    WHOOPSleepRow(
        sleep: nil,
        isLoading: true
    )
    .padding()
}

#Preview("Error State") {
    WHOOPErrorView(errorMessage: "Connection timeout") { }
        .padding()
}
