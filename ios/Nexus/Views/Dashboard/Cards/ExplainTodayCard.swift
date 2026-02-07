import SwiftUI

/// Shows the daily briefing from life.explain_today() - read-only summary
struct ExplainTodayCard: View {
    let explainToday: ExplainToday?

    var body: some View {
        if let data = explainToday, data.hasData {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.title3)
                        .foregroundColor(.nexusPrimary)
                    Text("Today's Briefing")
                        .font(.headline)
                    Spacer()
                    if let completeness = data.dataCompleteness {
                        Text("\(Int(completeness * 100))% data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(data.briefing)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !data.dataGaps.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Missing: \(data.dataGaps.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
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
}
