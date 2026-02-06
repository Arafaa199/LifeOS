import SwiftUI

/// Fasting timer card with start/break button and passive IF tracking
struct FastingCardView: View {
    let fasting: FastingStatus?
    let fastingElapsed: String
    let isLoading: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Main fasting display
            HStack(spacing: 12) {
                // Timer icon with progress ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        .frame(width: 44, height: 44)

                    // Progress ring (if tracking)
                    if let progress = fasting?.fastingGoalProgress {
                        Circle()
                            .trim(from: 0, to: progress.progress)
                            .stroke(
                                progressColor(for: progress.progress),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                    }

                    // Center icon
                    Image(systemName: fasting?.isActive == true ? "timer" : "fork.knife")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(fasting?.isActive == true ? .orange : .secondary)
                        .symbolEffect(.pulse, isActive: fasting?.isActive == true)
                }

                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    if fasting?.isActive == true {
                        // Explicit fasting session
                        Text(fasting?.elapsedFormatted ?? "--:--")
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundColor(.primary)
                        Text("Fasting")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if let hours = fasting?.hoursSinceMeal, hours > 0 {
                        // Passive tracking: hours since last meal
                        Text(fasting?.sinceMealFormatted ?? "--:--")
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundColor(.primary)
                        Text("Since last meal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // No data
                        Text("No meals logged")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action button
                Button {
                    onToggle()
                } label: {
                    Text(fasting?.isActive == true ? "Break" : "Start")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(fasting?.isActive == true ? Color.orange : Color.accentColor)
                        .cornerRadius(8)
                }
                .disabled(isLoading)
                .opacity(isLoading ? 0.6 : 1)
            }

            // Goal progress indicator (when tracking passively with significant hours)
            if let progress = fasting?.fastingGoalProgress, !fasting!.isActive, progress.hours >= 12 {
                HStack(spacing: 8) {
                    ForEach([16, 18, 20], id: \.self) { goal in
                        goalBadge(goal: goal, currentHours: progress.hours)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func progressColor(for progress: Double) -> Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.75 {
            return .orange
        } else {
            return .accentColor
        }
    }

    @ViewBuilder
    private func goalBadge(goal: Int, currentHours: Double) -> some View {
        let achieved = currentHours >= Double(goal)
        HStack(spacing: 4) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(achieved ? .green : .secondary)
            Text("\(goal)h")
                .font(.caption2.weight(.medium))
                .foregroundColor(achieved ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(achieved ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

#Preview {
    VStack(spacing: 20) {
        // No data state
        FastingCardView(
            fasting: nil,
            fastingElapsed: "--:--",
            isLoading: false,
            onToggle: {}
        )

        // Active explicit fasting session
        FastingCardView(
            fasting: FastingStatus(
                isActive: true,
                sessionId: 1,
                startedAt: nil,
                elapsedHours: 14.5,
                hoursSinceMeal: 16.2,
                lastMealAt: nil
            ),
            fastingElapsed: "14:30",
            isLoading: false,
            onToggle: {}
        )

        // Passive tracking (16h+ since meal)
        FastingCardView(
            fasting: FastingStatus(
                isActive: false,
                sessionId: nil,
                startedAt: nil,
                elapsedHours: nil,
                hoursSinceMeal: 17.5,
                lastMealAt: "2026-02-06T08:00:00Z"
            ),
            fastingElapsed: "--:--",
            isLoading: false,
            onToggle: {}
        )

        // Short time since meal (no goal badges)
        FastingCardView(
            fasting: FastingStatus(
                isActive: false,
                sessionId: nil,
                startedAt: nil,
                elapsedHours: nil,
                hoursSinceMeal: 4.5,
                lastMealAt: "2026-02-06T12:00:00Z"
            ),
            fastingElapsed: "--:--",
            isLoading: false,
            onToggle: {}
        )
    }
    .padding()
}
