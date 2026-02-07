import SwiftUI
import Charts

struct SpendingChartsView: View {
    let categoryBreakdown: [String: Double]
    let totalSpent: Double

    var sortedCategories: [(category: String, amount: Double)] {
        categoryBreakdown.map { ($0.key, $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Spending by Category")
                .font(.headline)

            if #available(iOS 16.0, *) {
                // Pie Chart
                Chart(sortedCategories, id: \.category) { item in
                    SectorMark(
                        angle: .value("Amount", abs(item.amount)),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                    .annotation(position: .overlay) {
                        Text(String(format: "%.0f%%", (abs(item.amount) / abs(totalSpent)) * 100))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 250)
                .chartLegend(position: .bottom, alignment: .center, spacing: 12)

                // Bar Chart
                Chart(sortedCategories, id: \.category) { item in
                    BarMark(
                        x: .value("Amount", abs(item.amount))
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                    .annotation(position: .trailing) {
                        Text(String(format: "AED %.0f", abs(item.amount)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(sortedCategories.count * 40))
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
            } else {
                // Fallback for iOS 15
                ForEach(sortedCategories, id: \.category) { item in
                    CategoryBar(
                        category: item.category,
                        amount: item.amount,
                        total: totalSpent
                    )
                }
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }
}

// Fallback view for iOS 15
struct CategoryBar: View {
    let category: String
    let amount: Double
    let total: Double

    private var percentage: Double {
        abs(amount) / abs(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.capitalized)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "AED %.0f", abs(amount)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 20)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(NexusTheme.Colors.accent.gradient)
                        .frame(width: geometry.size.width * percentage, height: 20)
                        .cornerRadius(4)

                    Text(String(format: "%.0f%%", percentage * 100))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                }
            }
            .frame(height: 20)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SpendingChartsView(
        categoryBreakdown: [
            "Grocery": 1250,
            "Restaurant": 850,
            "Transport": 320,
            "Utilities": 150
        ],
        totalSpent: 2570
    )
}
