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
                    color: .yellow,
                    text: fallback,
                    confidence: nil,
                    days: nil
                )
            }
        } else {
            VStack(spacing: 10) {
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if let confidence, let days {
                    HStack(spacing: 6) {
                        Text(confidence)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(confidenceColor(confidence))
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(days)d sample")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func insightColor(_ hint: String?) -> Color {
        switch hint {
        case "red": return .red
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "indigo": return .indigo
        case "green": return .green
        case "yellow": return .yellow
        default: return .yellow
        }
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence {
        case "high": return .green
        case "medium": return .orange
        default: return .secondary
        }
    }
}

#Preview {
    InsightsFeedView(
        insights: [],
        fallbackInsight: "High recovery - good day for intensity"
    )
    .padding()
}
