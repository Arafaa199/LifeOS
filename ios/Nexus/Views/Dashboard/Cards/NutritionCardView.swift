import SwiftUI

/// Nutrition card showing calories, meals, and water
struct NutritionCardView: View {
    let caloriesConsumed: Int?
    let mealsLogged: Int?
    let waterMl: Int?

    var body: some View {
        NavigationLink(destination: NutritionHistoryView()) {
            VStack(spacing: 12) {
                HStack {
                    Text("Nutrition")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    if let calories = caloriesConsumed, calories > 0 {
                        nutritionItem(value: "\(calories)", label: "cal", icon: "flame.fill", color: .orange)
                    }

                    if let meals = mealsLogged, meals > 0 {
                        nutritionItem(value: "\(meals)", label: "meals", icon: "fork.knife", color: .green)
                    }

                    if let water = waterMl, water > 0 {
                        nutritionItem(value: "\(water)", label: "ml", icon: "drop.fill", color: .blue)
                    }

                    Spacer()
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func nutritionItem(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
    }
}
