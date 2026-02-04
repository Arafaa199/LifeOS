import SwiftUI

/// Budget/spending status indicator with spent today and status
struct BudgetCardView: View {
    let spendTotal: Double?
    let spendVs7d: Double?
    let spendUnusual: Bool?
    let freshness: DomainFreshness?
    let hasData: Bool
    let currency: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(budgetStatusText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(budgetStatusColor)

            Text(spentTodayText)
                .font(.caption)
                .foregroundColor(.secondary)

            if let freshness {
                Text(freshness.syncTimeLabel)
                    .font(.caption2)
                    .foregroundColor(freshness.isStale ? .orange : .secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var spentToday: Double {
        spendTotal ?? 0
    }

    private var spentTodayText: String {
        if spentToday == 0 {
            return "No spending today"
        }
        return formatCurrency(abs(spentToday), currency: currency) + " today"
    }

    private var budgetStatusText: String {
        guard hasData else { return "No data" }

        if spendUnusual == true {
            return "Unusual spending"
        }

        if let vsAvg = spendVs7d, vsAvg > 50 {
            return "High spend day"
        }

        if spentToday == 0 {
            return "No spend"
        }

        return "Normal"
    }

    private var budgetStatusColor: Color {
        guard hasData else { return .gray }

        if spendUnusual == true { return .red }
        if let vsAvg = spendVs7d, vsAvg > 50 { return .orange }
        return .green
    }
}

#Preview {
    BudgetCardView(
        spendTotal: 150.0,
        spendVs7d: 25.0,
        spendUnusual: false,
        freshness: nil,
        hasData: true,
        currency: "AED"
    )
    .padding()
}
