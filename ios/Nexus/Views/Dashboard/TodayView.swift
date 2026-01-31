import SwiftUI

/// Canonical "Today" screen - frozen design, no customization
/// Shows: Recovery + Budget status, up to 3 ranked insights
struct TodayView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Offline indicator (minimal)
                    if !networkMonitor.isConnected {
                        offlineBanner
                    }

                    // Stale data banner
                    if viewModel.hasAnyStaleData && !viewModel.isForegroundRefreshing {
                        staleBanner
                    }

                    // No data state
                    if viewModel.dashboardPayload == nil && !viewModel.isLoading {
                        noDataView
                    } else {
                        // Pending meal confirmations
                        if let pendingMeal = viewModel.pendingMeals.first {
                            mealConfirmationSection(meal: pendingMeal)
                        }

                        // Top state: Recovery + Budget
                        stateCard

                        // Insights feed
                        insightsFeed
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .overlay(alignment: .top) {
                if viewModel.isForegroundRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Refreshing...")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.top, 8)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .refreshable {
                await viewModel.refresh()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
        }
    }

    // MARK: - Meal Confirmation Section

    private func mealConfirmationSection(meal: InferredMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirm Meal")
                .font(.headline)
                .foregroundColor(.primary)

            MealConfirmationView(
                meal: meal,
                onConfirm: {
                    Task {
                        await viewModel.confirmMeal(meal, action: "confirmed")
                    }
                },
                onSkip: {
                    Task {
                        await viewModel.confirmMeal(meal, action: "skipped")
                    }
                }
            )
        }
    }

    // MARK: - Offline Banner (minimal)

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("Offline")
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    // MARK: - Stale Data Banner

    private var staleBanner: some View {
        Button {
            viewModel.forceRefresh()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text(staleBannerText)
                    .font(.caption.weight(.medium))
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var staleBannerText: String {
        if viewModel.foregroundRefreshFailed, let formatted = viewModel.lastUpdatedFormatted {
            return "Showing data from \(formatted)"
        }
        let freshness = viewModel.dashboardPayload?.dataFreshness
        var staleNames: [String] = []
        if freshness?.health?.isStale == true { staleNames.append("Health") }
        if freshness?.finance?.isStale == true { staleNames.append("Finance") }
        if !staleNames.isEmpty {
            return "\(staleNames.joined(separator: " & ")) data delayed"
        }
        return "Data may be outdated"
    }

    // MARK: - No Data View

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Waiting for data")
                .font(.headline)

            Text("Pull down to refresh, or check Settings > Sync Center")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.forceRefresh()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 60)
    }

    // MARK: - State Card (Recovery + Budget)

    private var stateCard: some View {
        VStack(spacing: 16) {
            // Recovery row
            HStack {
                recoveryIndicator
                Spacer()
                budgetIndicator
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var recoveryIndicator: some View {
        HStack(spacing: 12) {
            // Recovery ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: recoveryProgress)
                    .stroke(recoveryColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Text(recoveryText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(recoveryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery")
                    .font(.subheadline.weight(.medium))

                if recoveryScore == nil {
                    let healthStatus = viewModel.dashboardPayload?.dataFreshness?.health?.status
                    if healthStatus == "healthy" || healthStatus == nil {
                        Text("Pending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let sleep = viewModel.dashboardPayload?.todayFacts?.sleepMinutes {
                    Text(formatSleep(sleep))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let freshness = viewModel.healthFreshness {
                    Text(freshness.syncTimeLabel)
                        .font(.caption2)
                        .foregroundColor(freshness.isStale ? .orange : .secondary)
                }
            }
        }
    }

    private var budgetIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(budgetStatusText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(budgetStatusColor)

            Text(spentTodayText)
                .font(.caption)
                .foregroundColor(.secondary)

            if let freshness = viewModel.financeFreshness {
                Text(freshness.syncTimeLabel)
                    .font(.caption2)
                    .foregroundColor(freshness.isStale ? .orange : .secondary)
            }
        }
    }

    // MARK: - Insights Feed

    @ViewBuilder
    private var insightsFeed: some View {
        let insights = viewModel.dashboardPayload?.dailyInsights?.rankedInsights ?? []

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

    private var fallbackInsight: String? {
        let facts = viewModel.dashboardPayload?.todayFacts
        if facts?.spendUnusual == true {
            return "Unusual spending: " + formatCurrency(spentToday, currency: AppSettings.shared.defaultCurrency) + " today"
        }
        if let score = recoveryScore, score < 34 { return "Low recovery — consider a rest day" }
        if let score = recoveryScore, score >= 67 { return "High recovery — good day for intensity" }
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 {
            return "Spending \(Int(vsAvg))% above your 7-day average"
        }
        return nil
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

    // MARK: - Computed Properties

    private var recoveryScore: Int? {
        viewModel.dashboardPayload?.todayFacts?.recoveryScore
    }

    private var recoveryProgress: CGFloat {
        guard let score = recoveryScore else { return 0 }
        return CGFloat(score) / 100.0
    }

    private var recoveryText: String {
        guard let score = recoveryScore else {
            // If health feed is healthy, cycle just hasn't closed yet
            let healthStatus = viewModel.dashboardPayload?.dataFreshness?.health?.status
            if healthStatus == "healthy" || healthStatus == nil {
                return "..."
            }
            return "--"
        }
        return "\(score)%"
    }

    private var recoveryColor: Color {
        guard let score = recoveryScore else {
            let healthStatus = viewModel.dashboardPayload?.dataFreshness?.health?.status
            if healthStatus == "healthy" || healthStatus == nil {
                return .secondary
            }
            return .gray
        }
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }

    private var spentToday: Double {
        viewModel.dashboardPayload?.todayFacts?.spendTotal ?? 0
    }

    private var spentTodayText: String {
        if spentToday == 0 {
            return "No spending today"
        }
        return formatCurrency(abs(spentToday), currency: AppSettings.shared.defaultCurrency) + " today"
    }

    private var budgetStatusText: String {
        guard viewModel.dashboardPayload != nil else { return "No data" }
        let facts = viewModel.dashboardPayload?.todayFacts

        // Check for unusual spending flag
        if facts?.spendUnusual == true {
            return "Unusual spending"
        }

        // Check vs 7-day average (spendVs7d is percentage change)
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 {
            return "High spend day"
        }

        if spentToday == 0 {
            return "No spend"
        }

        return "Normal"
    }

    private var budgetStatusColor: Color {
        guard viewModel.dashboardPayload != nil else { return .gray }
        let facts = viewModel.dashboardPayload?.todayFacts

        if facts?.spendUnusual == true { return .red }
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 { return .orange }
        return .green
    }


    // MARK: - Helpers

    private func formatSleep(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m sleep"
        } else if hours > 0 {
            return "\(hours)h sleep"
        }
        return "\(mins)m sleep"
    }
}

#Preview {
    TodayView(viewModel: DashboardViewModel())
}
