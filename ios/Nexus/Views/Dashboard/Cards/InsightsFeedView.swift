import SwiftUI

/// Ranked insights feed with fallback insight generation
struct InsightsFeedView: View {
    let insights: [RankedInsight]
    let fallbackInsight: String?

    var body: some View {
        if insights.isEmpty {
            if let fallback = fallbackInsight {
                insightRow(
                    icon: "lightbulb.fill",
                    color: NexusTheme.Colors.Semantic.amber,
                    text: fallback,
                    confidence: nil,
                    days: nil
                )
            }
        } else {
            VStack(spacing: NexusTheme.Spacing.sm) {
                ForEach(insights) { insight in
                    insightRow(
                        icon: insight.icon ?? "lightbulb.fill",
                        color: insightColor(insight.color),
                        text: insight.description,
                        confidence: insight.confidence,
                        days: insight.daysSampled
                    )
                }
            }
        }
    }

    private func insightRow(icon: String, color: Color, text: String, confidence: String?, days: Int?) -> some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 18))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                if let confidence, let days {
                    HStack(spacing: NexusTheme.Spacing.xxs) {
                        Text(confidence)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(confidenceColor(confidence))
                        Text("\u{2022}")
                            .font(.system(size: 10))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                        Text("\(days)d sample")
                            .font(.system(size: 10))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    private func insightColor(_ hint: String?) -> Color {
        switch hint {
        case "red": return NexusTheme.Colors.Semantic.red
        case "orange": return NexusTheme.Colors.Semantic.amber
        case "blue": return NexusTheme.Colors.Semantic.blue
        case "purple": return NexusTheme.Colors.Semantic.purple
        case "indigo": return NexusTheme.Colors.Semantic.purple
        case "green": return NexusTheme.Colors.Semantic.green
        case "yellow": return NexusTheme.Colors.Semantic.amber
        default: return NexusTheme.Colors.Semantic.amber
        }
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence {
        case "high": return NexusTheme.Colors.Semantic.green
        case "medium": return NexusTheme.Colors.Semantic.amber
        default: return NexusTheme.Colors.textSecondary
        }
    }
}

#Preview {
    InsightsFeedView(
        insights: [],
        fallbackInsight: "High recovery - good day for intensity"
    )
    .padding()
    .background(NexusTheme.Colors.background)
}
