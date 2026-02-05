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
        VStack(alignment: .trailing, spacing: 6) {
            // Spend amount as primary number
            Text(spentTodayText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Status chip
            HStack(spacing: 4) {
                Image(systemName: budgetStatusIcon)
                    .font(.system(size: 9))
                Text(budgetStatusText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundColor(budgetStatusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(budgetStatusColor.opacity(0.12))
            .cornerRadius(6)

            if let freshness {
                Text(freshness.syncTimeLabel)
                    .font(.caption2)
                    .foregroundColor(freshness.isStale ? .nexusWarning : .secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var spentToday: Double {
        spendTotal ?? 0
    }

    private var spentTodayText: String {
        if spentToday == 0 {
            return "No spend"
        }
        return formatCurrency(abs(spentToday), currency: currency)
    }

    private var budgetStatusIcon: String {
        guard hasData else { return "minus.circle" }
        if spendUnusual == true { return "exclamationmark.triangle.fill" }
        if let vsAvg = spendVs7d, vsAvg > 50 { return "arrow.up.circle.fill" }
        if spentToday == 0 { return "checkmark.circle.fill" }
        return "checkmark.circle.fill"
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

        if spendUnusual == true { return .nexusError }
        if let vsAvg = spendVs7d, vsAvg > 50 { return .nexusWarning }
        return .nexusSuccess
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
