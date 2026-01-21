import SwiftUI

/// Daily summary cards showing Calories, Protein, Water, Weight, and Mood
struct SummaryCardsSection: View {
    let summary: DailySummary
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            NexusStatCard(
                title: "Calories",
                value: "\(summary.totalCalories)",
                unit: "kcal",
                icon: "flame.fill",
                color: .nexusFood,
                isLoading: isLoading
            )

            NexusStatCard(
                title: "Protein",
                value: String(format: "%.1f", summary.totalProtein),
                unit: "g",
                icon: "bolt.fill",
                color: .nexusProtein,
                isLoading: isLoading
            )

            NexusStatCard(
                title: "Water",
                value: "\(summary.totalWater)",
                unit: "ml",
                icon: "drop.fill",
                color: .nexusWater,
                isLoading: isLoading
            )

            if let weight = summary.latestWeight {
                NexusStatCard(
                    title: "Weight",
                    value: String(format: "%.1f", weight),
                    unit: "kg",
                    icon: "scalemass.fill",
                    color: .nexusWeight,
                    isLoading: isLoading
                )
            }

            if let mood = summary.mood {
                NexusStatCard(
                    title: "Mood",
                    value: "\(mood)",
                    unit: "/ 10",
                    icon: "face.smiling.fill",
                    color: .nexusMood,
                    isLoading: isLoading
                )
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    SummaryCardsSection(
        summary: DailySummary(
            totalCalories: 1850,
            totalProtein: 120.5,
            totalWater: 2500,
            latestWeight: 78.5,
            mood: 7
        ),
        isLoading: false
    )
}
