import SwiftUI

/// Compact mood/energy card for dashboard
struct MoodCardView: View {
    let mood: MoodSummary?

    var body: some View {
        if let mood = mood, mood.hasData {
            HStack(spacing: NexusTheme.Spacing.lg) {
                // Mood
                VStack(spacing: NexusTheme.Spacing.xxxs) {
                    Text(mood.moodEmoji)
                        .font(.system(size: 28))
                    Text("Mood")
                        .font(.system(size: 10))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                    if let score = mood.moodScore {
                        Text("\(score)/10")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(width: 1, height: 50)
                    .accessibilityHidden(true)

                // Energy
                VStack(spacing: NexusTheme.Spacing.xxxs) {
                    Text(mood.energyEmoji)
                        .font(.system(size: 28))
                    Text("Energy")
                        .font(.system(size: 10))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                    if let score = mood.energyScore {
                        Text("\(score)/10")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                NavigationLink(destination: MoodLogView()) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(NexusTheme.Colors.accent)
                }
                .accessibilityLabel("Log mood")
            }
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        } else {
            // No mood logged - show prompt
            NavigationLink(destination: MoodLogView()) {
                HStack(spacing: NexusTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(NexusTheme.Colors.accent.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18))
                            .foregroundColor(NexusTheme.Colors.accent)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log your mood")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)
                        Text("Track how you feel today")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NexusTheme.Colors.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(NexusTheme.Spacing.lg)
                .background(NexusTheme.Colors.card)
                .cornerRadius(NexusTheme.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                        .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    VStack {
        MoodCardView(mood: MoodSummary(
            moodScore: 7,
            energyScore: 6,
            loggedAt: "2026-02-07T10:30:00+04:00",
            notes: nil
        ))
        MoodCardView(mood: nil)
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
