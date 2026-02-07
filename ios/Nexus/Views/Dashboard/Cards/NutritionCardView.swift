import SwiftUI

/// Nutrition card showing calories, meals, and water
struct NutritionCardView: View {
    let caloriesConsumed: Int?
    let mealsLogged: Int?
    let waterMl: Int?

    var body: some View {
        NavigationLink(destination: NutritionHistoryView()) {
            VStack(spacing: NexusTheme.Spacing.md) {
                HStack {
                    NexusTheme.Typography.cardTitle("Nutrition")
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }

                HStack(spacing: NexusTheme.Spacing.lg) {
                    if let calories = caloriesConsumed, calories > 0 {
                        nutritionItem(value: "\(calories)", label: "cal", icon: "flame.fill", color: NexusTheme.Colors.Semantic.amber)
                    }

                    if let meals = mealsLogged, meals > 0 {
                        nutritionItem(value: "\(meals)", label: "meals", icon: "fork.knife", color: NexusTheme.Colors.Semantic.green)
                    }

                    if let water = waterMl, water > 0 {
                        nutritionItem(value: "\(water)", label: "ml", icon: "drop.fill", color: NexusTheme.Colors.Semantic.blue)
                    }

                    Spacer()
                }
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

    private func nutritionItem(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: NexusTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }
        }
    }
}

#Preview {
    NavigationView {
        NutritionCardView(
            caloriesConsumed: 1500,
            mealsLogged: 3,
            waterMl: 2000
        )
        .padding()
        .background(NexusTheme.Colors.background)
    }
}
