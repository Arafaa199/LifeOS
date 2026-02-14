import SwiftUI

/// Nutrition card showing calories, protein, meals, and water
struct NutritionCardView: View {
    let caloriesConsumed: Int?
    let proteinG: Double?
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
                        .accessibilityHidden(true)
                }

                HStack(spacing: NexusTheme.Spacing.lg) {
                    if let calories = caloriesConsumed, calories > 0 {
                        nutritionItem(value: "\(calories)", label: "cal", icon: "flame.fill", color: NexusTheme.Colors.Semantic.amber)
                    }

                    if let protein = proteinG, protein > 0 {
                        nutritionItem(value: "\(Int(protein))g", label: "protein", icon: "figure.strengthtraining.traditional", color: NexusTheme.Colors.Semantic.purple)
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
        .accessibilityLabel(nutritionAccessibilityLabel)
    }

    private var nutritionAccessibilityLabel: String {
        var parts: [String] = ["Nutrition"]
        if let cal = caloriesConsumed, cal > 0 { parts.append("\(cal) calories") }
        if let p = proteinG, p > 0 { parts.append("\(Int(p)) grams protein") }
        if let m = mealsLogged, m > 0 { parts.append("\(m) meals") }
        if let w = waterMl, w > 0 { parts.append("\(w) milliliters water") }
        return parts.joined(separator: ", ")
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
            proteinG: 85.5,
            mealsLogged: 3,
            waterMl: 2000
        )
        .padding()
        .background(NexusTheme.Colors.background)
    }
}
