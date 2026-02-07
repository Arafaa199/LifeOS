import SwiftUI

/// Shows the daily briefing from life.explain_today() - read-only summary
struct ExplainTodayCard: View {
    let explainToday: ExplainToday?

    var body: some View {
        if let data = explainToday, data.hasData {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.md) {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.system(size: 18))
                        .foregroundColor(NexusTheme.Colors.accent)
                    Text("Today's Briefing")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(NexusTheme.Colors.textPrimary)
                    Spacer()
                    if let completeness = data.dataCompleteness {
                        Text("\(Int(completeness * 100))% data")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                            .padding(.horizontal, NexusTheme.Spacing.xs)
                            .padding(.vertical, 3)
                            .background(NexusTheme.Colors.cardAlt)
                            .cornerRadius(NexusTheme.Radius.xs)
                    }
                }

                Text(data.briefing)
                    .font(.system(size: 13.5))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !data.dataGaps.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        Text("Missing: \(data.dataGaps.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
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
    }
}

#Preview {
    ExplainTodayCard(explainToday: ExplainToday(
        targetDate: "2026-02-07",
        hasData: true,
        briefing: "Moderate recovery (59%) after only 5.6h sleep. Spent 148 AED.",
        dataGaps: [],
        dataCompleteness: 0.72,
        computedAt: nil,
        assertions: nil,
        health: nil,
        finance: nil,
        activity: nil,
        nutrition: nil
    ))
    .padding()
    .background(NexusTheme.Colors.background)
}
