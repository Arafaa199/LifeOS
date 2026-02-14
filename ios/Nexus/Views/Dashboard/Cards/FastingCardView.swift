import SwiftUI
import UIKit

/// Fasting timer card with start/break button and passive IF tracking
struct FastingCardView: View {
    let fasting: FastingStatus?
    let fastingElapsed: String
    let isLoading: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.md) {
            // Main fasting display
            HStack(spacing: NexusTheme.Spacing.md) {
                // Timer icon with progress ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(NexusTheme.Colors.divider, lineWidth: 4)
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
                            .animation(.spring(duration: 0.5), value: progress.progress)
                    }

                    // Center icon
                    Image(systemName: fasting?.isActive == true ? "timer" : "fork.knife")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(fasting?.isActive == true ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.textTertiary)
                        .symbolEffect(.pulse, isActive: fasting?.isActive == true)
                        .accessibilityHidden(true)
                }

                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    if fasting?.isActive == true {
                        // Explicit fasting session
                        Text(fasting?.elapsedFormatted ?? "--:--")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                        Text("Fasting")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    } else if let hours = fasting?.hoursSinceMeal, hours > 0 {
                        // Passive tracking: hours since last meal
                        Text(fasting?.sinceMealFormatted ?? "--:--")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                        Text("Since last meal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    } else {
                        // No data
                        Text("No meals logged")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
                }

                Spacer()

                // Action button
                Button {
                    NexusTheme.Haptics.medium()
                    onToggle()
                } label: {
                    Text(fasting?.isActive == true ? "Break" : "Start")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, NexusTheme.Spacing.lg)
                        .padding(.vertical, NexusTheme.Spacing.xs)
                        .background(fasting?.isActive == true ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.accent)
                        .cornerRadius(NexusTheme.Radius.md)
                }
                .disabled(isLoading)
                .opacity(isLoading ? 0.6 : 1)
                .accessibilityLabel(fasting?.isActive == true ? "Break fast" : "Start fasting")
            }

            // Goal progress indicator (when tracking passively with significant hours)
            if let fasting = fasting, let progress = fasting.fastingGoalProgress, !fasting.isActive, progress.hours >= 12 {
                HStack(spacing: NexusTheme.Spacing.xs) {
                    ForEach([16, 18, 20], id: \.self) { goal in
                        goalBadge(goal: goal, currentHours: progress.hours)
                    }
                    Spacer()
                }
                .padding(.top, NexusTheme.Spacing.xxxs)
            }
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fasting")
    }

    private func progressColor(for progress: Double) -> Color {
        if progress >= 1.0 {
            return NexusTheme.Colors.Semantic.green
        } else if progress >= 0.75 {
            return NexusTheme.Colors.Semantic.amber
        } else {
            return NexusTheme.Colors.accent
        }
    }

    @ViewBuilder
    private func goalBadge(goal: Int, currentHours: Double) -> some View {
        let achieved = currentHours >= Double(goal)
        HStack(spacing: 4) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(achieved ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.textTertiary)
            Text("\(goal)h")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(achieved ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.textTertiary)
        }
        .padding(.horizontal, NexusTheme.Spacing.xs)
        .padding(.vertical, NexusTheme.Spacing.xxxs)
        .background(achieved ? NexusTheme.Colors.Semantic.green.opacity(0.15) : NexusTheme.Colors.cardAlt)
        .cornerRadius(NexusTheme.Radius.xs)
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
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
