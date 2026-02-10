import SwiftUI

struct WeeklyReviewCardView: View {
    let review: WeeklyReview?

    var body: some View {
        if let review = review {
            HStack(spacing: NexusTheme.Spacing.md) {
                // Score circle
                ZStack {
                    Circle()
                        .fill(scoreColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text("\(review.score)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Text("Weekly Review")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)

                        Text(weekLabel)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                    }

                    if let summary = review.summaryText {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Score out of 10
                Text("/10")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
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

    private var scoreColor: Color {
        guard let review = review else { return NexusTheme.Colors.textTertiary }
        if review.score >= 8 { return NexusTheme.Colors.Semantic.green }
        if review.score >= 5 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var weekLabel: String {
        guard let review = review else { return "" }
        let start = formatShortDate(review.weekStart)
        let end = formatShortDate(review.weekEnd)
        return "\(start) – \(end)"
    }

    private func formatShortDate(_ dateString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateString) else { return dateString }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }
}

#Preview {
    VStack {
        WeeklyReviewCardView(review: WeeklyReview(
            weekStart: "2026-02-02",
            weekEnd: "2026-02-08",
            score: 8,
            summaryText: "Outstanding week. Recovery averaged 72% and trending up. Sleep solid at 7.5h avg. 2 BJJ sessions (4-week streak). Spent 1200 AED, down from last week. Habits on point at 85%.",
            avgRecovery: 72,
            avgSleepHours: 7.5,
            bjjSessions: 2,
            totalSpent: 1200,
            habitCompletionPct: 85,
            spendingTrend: "decreasing",
            recoveryTrend: "improving",
            generatedAt: "2026-02-09T21:00:00Z"
        ))
        WeeklyReviewCardView(review: WeeklyReview(
            weekStart: "2026-02-02",
            weekEnd: "2026-02-08",
            score: 4,
            summaryText: "Tough week. Recovery dropped to 38%. Sleep needs work at 5.8h avg.",
            avgRecovery: 38,
            avgSleepHours: 5.8,
            bjjSessions: 0,
            totalSpent: 3500,
            habitCompletionPct: 35,
            spendingTrend: "increasing",
            recoveryTrend: "declining",
            generatedAt: "2026-02-09T21:00:00Z"
        ))
        WeeklyReviewCardView(review: nil)
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
