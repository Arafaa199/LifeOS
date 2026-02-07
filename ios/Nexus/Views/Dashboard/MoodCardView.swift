import SwiftUI

/// Compact mood/energy card for dashboard
struct MoodCardView: View {
    let mood: MoodSummary?

    var body: some View {
        if let mood = mood, mood.hasData {
            HStack(spacing: 16) {
                // Mood
                VStack(spacing: 4) {
                    Text(mood.moodEmoji)
                        .font(.system(size: 28))
                    Text("Mood")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let score = mood.moodScore {
                        Text("\(score)/10")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 50)

                // Energy
                VStack(spacing: 4) {
                    Text(mood.energyEmoji)
                        .font(.system(size: 28))
                    Text("Energy")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let score = mood.energyScore {
                        Text("\(score)/10")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                NavigationLink(destination: MoodLogView()) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.nexusMood)
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(12)
        } else {
            // No mood logged - show prompt
            NavigationLink(destination: MoodLogView()) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.nexusMood.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.nexusMood)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log your mood")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text("Track how you feel today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(12)
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
    .background(Color.nexusBackground)
}
