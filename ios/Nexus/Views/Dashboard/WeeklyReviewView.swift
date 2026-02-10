import SwiftUI

struct WeeklyReviewView: View {
    let review: WeeklyReview

    var body: some View {
        ScrollView {
            VStack(spacing: NexusTheme.Spacing.lg) {
                // Score header
                scoreHeader

                // Summary
                if let summary = review.summaryText {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                        .padding(NexusTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NexusTheme.Colors.card)
                        .cornerRadius(NexusTheme.Radius.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                        )
                }

                // Metrics grid
                metricsGrid

                // Trends
                trendsSection
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.top, NexusTheme.Spacing.md)
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Weekly Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: NexusTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                VStack(spacing: 0) {
                    Text("\(review.score)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("/10")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                }
            }

            Text(weekLabel)
                .font(.system(size: 13))
                .foregroundColor(NexusTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NexusTheme.Spacing.md)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: NexusTheme.Spacing.md) {
            metricCell(
                icon: "heart.fill",
                color: NexusTheme.Colors.Semantic.red,
                label: "Recovery",
                value: review.avgRecovery.map { "\(Int($0))%" } ?? "—"
            )
            metricCell(
                icon: "bed.double.fill",
                color: NexusTheme.Colors.Semantic.purple,
                label: "Sleep",
                value: review.avgSleepHours.map { String(format: "%.1fh", $0) } ?? "—"
            )
            metricCell(
                icon: "figure.martial.arts",
                color: NexusTheme.Colors.Semantic.amber,
                label: "BJJ",
                value: review.bjjSessions.map { "\($0) sessions" } ?? "—"
            )
            metricCell(
                icon: "banknote.fill",
                color: NexusTheme.Colors.Semantic.green,
                label: "Spent",
                value: review.totalSpent.map { "\(Int($0)) AED" } ?? "—"
            )
            metricCell(
                icon: "checkmark.circle.fill",
                color: NexusTheme.Colors.Semantic.blue,
                label: "Habits",
                value: review.habitCompletionPct.map { "\(Int($0))%" } ?? "—"
            )
        }
    }

    private func metricCell(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: NexusTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(NexusTheme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(NexusTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Trends

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
            if let recoveryTrend = review.recoveryTrend, recoveryTrend != "no_data" {
                trendRow(label: "Recovery", trend: recoveryTrend)
            }
            if let spendingTrend = review.spendingTrend, spendingTrend != "no_data" {
                trendRow(label: "Spending", trend: spendingTrend)
            }
        }
        .padding(NexusTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }

    private func trendRow(label: String, trend: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: trendIcon(trend))
                    .font(.system(size: 11))
                Text(trend.capitalized)
                    .font(.system(size: 12))
            }
            .foregroundColor(trendColor(trend))
        }
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        if review.score >= 8 { return NexusTheme.Colors.Semantic.green }
        if review.score >= 5 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var weekLabel: String {
        let start = formatDate(review.weekStart)
        let end = formatDate(review.weekEnd)
        return "\(start) – \(end)"
    }

    private func formatDate(_ dateString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateString) else { return dateString }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    private func trendIcon(_ trend: String) -> String {
        switch trend {
        case "improving", "decreasing": return "arrow.up.right"
        case "declining", "increasing": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "improving", "decreasing": return NexusTheme.Colors.Semantic.green
        case "declining", "increasing": return NexusTheme.Colors.Semantic.red
        default: return NexusTheme.Colors.textTertiary
        }
    }
}

#Preview {
    NavigationStack {
        WeeklyReviewView(review: WeeklyReview(
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
    }
}
