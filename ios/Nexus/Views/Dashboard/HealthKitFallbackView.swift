import SwiftUI

struct HealthKitSleepFallbackView: View {
    let sleepData: HealthKitManager.SleepData
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Fallback notice
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Sleep data from Apple Watch (WHOOP unavailable)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.nexusPrimary)
                }
            }
            .padding(.horizontal, 4)

            // Sleep data cards - first row
            HStack(spacing: 12) {
                HealthMetricCard(
                    title: "Sleep",
                    value: formatDuration(sleepData.asleepMinutes),
                    unit: "",
                    icon: "bed.double.fill",
                    color: .indigo,
                    isLoading: false
                )

                if sleepData.deepMinutes > 0 {
                    HealthMetricCard(
                        title: "Deep",
                        value: formatDuration(sleepData.deepMinutes),
                        unit: "",
                        icon: "moon.zzz.fill",
                        color: .blue,
                        isLoading: false
                    )
                }

                if sleepData.remMinutes > 0 {
                    HealthMetricCard(
                        title: "REM",
                        value: formatDuration(sleepData.remMinutes),
                        unit: "",
                        icon: "brain.head.profile",
                        color: .purple,
                        isLoading: false
                    )
                }
            }

            // Second row with efficiency if available
            if sleepData.sleepEfficiency > 0 {
                HStack(spacing: 12) {
                    HealthMetricCard(
                        title: "Efficiency",
                        value: String(format: "%.0f", sleepData.sleepEfficiency * 100),
                        unit: "%",
                        icon: "chart.bar.fill",
                        color: .cyan,
                        isLoading: false
                    )

                    if sleepData.awakeMinutes > 0 {
                        HealthMetricCard(
                            title: "Awake",
                            value: formatDuration(sleepData.awakeMinutes),
                            unit: "",
                            icon: "eye.fill",
                            color: .orange,
                            isLoading: false
                        )
                    }

                    // Spacer card if needed for alignment
                    if sleepData.awakeMinutes == 0 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}

// MARK: - HealthKit Data Row (Weight, Steps, Calories)

struct HealthKitDataRow: View {
    let weight: Double?
    let steps: Int
    let calories: Int
    let isLoading: Bool
    let hasWeightHistory: Bool
    let onWeightTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let weight = weight {
                HealthMetricCard(
                    title: "Weight",
                    value: String(format: "%.1f", weight),
                    unit: "kg",
                    icon: "scalemass.fill",
                    color: .nexusWeight,
                    isLoading: isLoading
                )
                .onTapGesture {
                    if hasWeightHistory {
                        onWeightTap()
                    }
                }
            }

            HealthMetricCard(
                title: "Steps",
                value: formatNumber(steps),
                unit: "",
                icon: "figure.walk",
                color: .green,
                isLoading: isLoading
            )

            HealthMetricCard(
                title: "Active Cal",
                value: "\(calories)",
                unit: "kcal",
                icon: "flame.fill",
                color: .orange,
                isLoading: isLoading
            )
        }
    }

    private func formatNumber(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fk", Double(number) / 1000) : "\(number)"
    }
}

// MARK: - HealthKit Connect Prompt

struct HealthKitConnectPrompt: View {
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundColor(.pink)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Apple Health")
                    .font(.subheadline.weight(.medium))
                Text("Sync weight & activity from Eufy, Apple Watch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
        .onTapGesture { onConnect() }
    }
}

#Preview("HealthKit Data Row") {
    HealthKitDataRow(
        weight: 108.25,
        steps: 8432,
        calories: 342,
        isLoading: false,
        hasWeightHistory: true,
        onWeightTap: { }
    )
    .padding()
}

#Preview("Connect Prompt") {
    HealthKitConnectPrompt { }
        .padding()
}
