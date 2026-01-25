import SwiftUI

/// Canonical "Today" screen - frozen design, no customization
/// Shows: Recovery + Budget status, one insight, nothing else
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

                    // Pending meal confirmations
                    if let pendingMeal = viewModel.pendingMeals.first {
                        mealConfirmationSection(meal: pendingMeal)
                    }

                    // Top state: Recovery + Budget
                    stateCard

                    // Single insight
                    if let insight = topInsight {
                        insightCard(insight)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
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

                if let sleep = viewModel.dashboardPayload?.todayFacts.sleepMinutes {
                    Text(formatSleep(sleep))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        }
    }

    // MARK: - Insight Card

    private func insightCard(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.title3)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Computed Properties

    private var recoveryScore: Int? {
        viewModel.dashboardPayload?.todayFacts.recoveryScore
    }

    private var recoveryProgress: CGFloat {
        guard let score = recoveryScore else { return 0 }
        return CGFloat(score) / 100.0
    }

    private var recoveryText: String {
        guard let score = recoveryScore else { return "--" }
        return "\(score)%"
    }

    private var recoveryColor: Color {
        guard let score = recoveryScore else { return .gray }
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }

    private var spentToday: Double {
        viewModel.dashboardPayload?.todayFacts.spendTotal ?? 0
    }

    private var spentTodayText: String {
        if spentToday == 0 {
            return "No spending today"
        }
        return String(format: "%.0f AED today", abs(spentToday))
    }

    private var budgetStatusText: String {
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
        let facts = viewModel.dashboardPayload?.todayFacts

        if facts?.spendUnusual == true { return .red }
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 { return .orange }
        return .green
    }

    private var topInsight: String? {
        let facts = viewModel.dashboardPayload?.todayFacts

        // Priority 1: Unusual spending
        if facts?.spendUnusual == true {
            let spent = Int(spentToday)
            return "Unusual spending detected: \(spent) AED today"
        }

        // Priority 2: Low recovery
        if let score = recoveryScore, score < 34 {
            return "Low recovery - consider a rest day"
        }

        // Priority 3: Good state
        if let score = recoveryScore, score >= 67 {
            return "High recovery - good day for intensity"
        }

        // Priority 4: High spend vs average
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 {
            return "Spending \(Int(vsAvg))% above your 7-day average"
        }

        return nil
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
