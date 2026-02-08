import SwiftUI
import Combine

/// Canonical "Today" screen - frozen design, no customization
/// Shows: Recovery + Budget status, up to 3 ranked insights
struct TodayView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var offlineQueue = OfflineQueue.shared
    @ObservedObject private var homeViewModel = HomeViewModel.shared
    @State private var isFastingLoading = false
    @State private var fastingElapsed: String = "--:--"
    @State private var showingQuickLog = false
    @State private var showingHomeControl = false
    @State private var fastingTimerCancellable: AnyCancellable?

    private let fastingTimer = Timer.publish(every: 1, on: .main, in: .common)

    var body: some View {
        ScrollView {
            VStack(spacing: NexusTheme.Spacing.lg) {
                // Status banners
                statusBanners

                // Main content
                if let error = viewModel.errorMessage, viewModel.dashboardPayload == nil {
                    ThemeEmptyState(
                        icon: "exclamationmark.triangle",
                        headline: "Something went wrong",
                        description: error,
                        ctaTitle: "Try Again",
                        ctaAction: viewModel.forceRefresh
                    )
                } else if viewModel.dashboardPayload == nil && !viewModel.isLoading {
                    ThemeEmptyState(
                        icon: "tray",
                        headline: "No Data Yet",
                        description: "Pull down to refresh and load your dashboard.",
                        ctaTitle: "Refresh",
                        ctaAction: viewModel.forceRefresh
                    )
                } else {
                    dashboardContent
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.top, NexusTheme.Spacing.md)
        }
        .overlay(alignment: .top) {
            if viewModel.isForegroundRefreshing {
                refreshingOverlay
            }
        }
        .background(NexusTheme.Colors.background)
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showingQuickLog) {
            QuickLogView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingHomeControl) {
            HomeControlView()
        }
        .onAppear {
            updateFastingElapsed()
            // Start timer when view appears
            fastingTimerCancellable = fastingTimer
                .autoconnect()
                .sink { _ in updateFastingElapsed() }
        }
        .onDisappear {
            // Stop timer when view disappears to prevent background updates
            fastingTimerCancellable?.cancel()
            fastingTimerCancellable = nil
        }
    }

    // MARK: - Status Banners

    @ViewBuilder
    private var statusBanners: some View {
        if !networkMonitor.isConnected {
            ThemeAlertBanner(message: "You're offline. \(offlineQueue.pendingItemCount) items pending sync.", icon: "wifi.slash", type: .warning)
        } else if offlineQueue.pendingItemCount > 0 {
            ThemeAlertBanner(message: "Syncing \(offlineQueue.pendingItemCount) item\(offlineQueue.pendingItemCount == 1 ? "" : "s")...", icon: "arrow.triangle.2.circlepath", type: .info)
        } else if viewModel.isFromCache && !viewModel.isForegroundRefreshing {
            ThemeAlertBanner(message: "Showing cached data from \(SyncCoordinator.shared.cacheAgeFormatted)", icon: "clock", type: .info)
        }

        if viewModel.hasAnyStaleData && !viewModel.isForegroundRefreshing {
            ThemeAlertBanner(message: staleBannerText, icon: "exclamationmark.circle", type: .warning)
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        // Meal confirmation
        if let pendingMeal = viewModel.pendingMeals.first {
            mealConfirmationSection(meal: pendingMeal)
        }

        // Daily Briefing
        ExplainTodayCard(explainToday: viewModel.dashboardPayload?.explainToday)

        // Status Card
        StateCardView(
            recoveryScore: viewModel.dashboardPayload?.todayFacts?.recoveryScore,
            sleepMinutes: viewModel.dashboardPayload?.todayFacts?.sleepMinutes,
            healthStatus: viewModel.dashboardPayload?.dataFreshness?.health?.status,
            healthFreshness: viewModel.healthFreshness,
            spendTotal: viewModel.dashboardPayload?.todayFacts?.spendTotal,
            spendVs7d: viewModel.dashboardPayload?.todayFacts?.spendVs7d,
            spendUnusual: viewModel.dashboardPayload?.todayFacts?.spendUnusual,
            financeFreshness: viewModel.financeFreshness,
            hasData: viewModel.dashboardPayload != nil,
            currency: AppSettings.shared.defaultCurrency,
            workoutCount: viewModel.dashboardPayload?.todayFacts?.workoutCount,
            workoutMinutes: viewModel.dashboardPayload?.todayFacts?.workoutMinutes,
            reminderSummary: viewModel.dashboardPayload?.reminderSummary
        )

        // Streaks
        StreakBadgesView(streaks: viewModel.dashboardPayload?.streaks)

        // Nutrition + Fasting
        nutritionAndFastingSection

        // Home
        HomeStatusCard(viewModel: homeViewModel, onTap: { showingHomeControl = true })

        // Music
        MusicCardView(music: viewModel.dashboardPayload?.musicToday)

        // Mood
        MoodCardView(mood: viewModel.dashboardPayload?.moodToday)

        // Medications
        MedicationsCardView(medications: viewModel.dashboardPayload?.medicationsToday)

        // Insights
        insightsSection
    }

    @ViewBuilder
    private var nutritionAndFastingSection: some View {
        if hasNutritionData || viewModel.dashboardPayload?.fasting != nil {
            VStack(spacing: NexusTheme.Spacing.md) {
                if hasNutritionData {
                    NutritionCardView(
                        caloriesConsumed: viewModel.dashboardPayload?.todayFacts?.caloriesConsumed,
                        mealsLogged: viewModel.dashboardPayload?.todayFacts?.mealsLogged,
                        waterMl: viewModel.dashboardPayload?.todayFacts?.waterMl
                    )
                }

                FastingCardView(
                    fasting: viewModel.dashboardPayload?.fasting,
                    fastingElapsed: fastingElapsed,
                    isLoading: isFastingLoading,
                    onToggle: toggleFasting
                )
            }
        } else {
            FastingCardView(
                fasting: viewModel.dashboardPayload?.fasting,
                fastingElapsed: fastingElapsed,
                isLoading: isFastingLoading,
                onToggle: toggleFasting
            )
        }
    }

    @ViewBuilder
    private var insightsSection: some View {
        if !insightsEmpty {
            todaySectionHeader("Insights")
        }

        InsightsFeedView(
            insights: viewModel.dashboardPayload?.dailyInsights?.rankedInsights ?? [],
            fallbackInsight: fallbackInsight
        )
    }

    // MARK: - Subviews

    private var refreshingOverlay: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(NexusTheme.Colors.accent)
            Text("Refreshing...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textSecondary)
        }
        .padding(.horizontal, NexusTheme.Spacing.lg)
        .padding(.vertical, NexusTheme.Spacing.xs)
        .background(.ultraThinMaterial)
        .cornerRadius(NexusTheme.Radius.card)
        .padding(.top, NexusTheme.Spacing.xs)
    }

    private func mealConfirmationSection(meal: InferredMeal) -> some View {
        ThemeTitledCard("Confirm Meal") {
            MealConfirmationView(
                meal: meal,
                onConfirm: { Task { await viewModel.confirmMeal(meal, action: "confirmed") } },
                onSkip: { Task { await viewModel.confirmMeal(meal, action: "skipped") } }
            )
        }
    }

    // MARK: - Fasting

    private func updateFastingElapsed() {
        guard let fasting = viewModel.dashboardPayload?.fasting,
              fasting.isActive,
              let startDate = fasting.startedAtDate else {
            fastingElapsed = "--:--"
            return
        }
        let elapsed = Date().timeIntervalSince(startDate)
        let totalMinutes = Int(elapsed / 60)
        fastingElapsed = String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func toggleFasting() {
        let isActive = viewModel.dashboardPayload?.fasting?.isActive == true
        isFastingLoading = true
        Task {
            do {
                if isActive { try await viewModel.breakFast() }
                else { try await viewModel.startFast() }
            } catch {
                viewModel.errorMessage = "Failed to toggle fasting: \(error.localizedDescription)"
            }
            isFastingLoading = false
        }
    }

    // MARK: - Computed Properties

    private var hasNutritionData: Bool {
        let facts = viewModel.dashboardPayload?.todayFacts
        return (facts?.mealsLogged ?? 0) > 0 || (facts?.waterMl ?? 0) > 0
    }

    private var insightsEmpty: Bool {
        let ranked = viewModel.dashboardPayload?.dailyInsights?.rankedInsights ?? []
        return ranked.isEmpty && fallbackInsight == nil
    }

    private func todaySectionHeader(_ title: String) -> some View {
        HStack {
            NexusTheme.Typography.cardTitle(title)
                .foregroundColor(NexusTheme.Colors.textTertiary)
            Spacer()
        }
        .padding(.top, NexusTheme.Spacing.xs)
    }

    private var staleBannerText: String {
        if viewModel.foregroundRefreshFailed, let formatted = viewModel.lastUpdatedFormatted {
            return "Showing data from \(formatted)"
        }
        let freshness = viewModel.dashboardPayload?.dataFreshness
        var staleNames: [String] = []
        if freshness?.health?.isStale == true { staleNames.append("Health") }
        if freshness?.finance?.isStale == true { staleNames.append("Finance") }
        if !staleNames.isEmpty { return "\(staleNames.joined(separator: " & ")) data delayed" }
        return "Data may be outdated"
    }

    private var fallbackInsight: String? {
        let facts = viewModel.dashboardPayload?.todayFacts
        let spentToday = facts?.spendTotal ?? 0
        if facts?.spendUnusual == true {
            return "Unusual spending: " + formatCurrency(spentToday, currency: AppSettings.shared.defaultCurrency) + " today"
        }
        if let score = facts?.recoveryScore, score < 34 { return "Low recovery — consider a rest day" }
        if let score = facts?.recoveryScore, score >= 67 { return "High recovery — good day for intensity" }
        if let vsAvg = facts?.spendVs7d, vsAvg > 50 {
            return "Spending \(Int(vsAvg))% above your 7-day average"
        }
        return nil
    }
}

#Preview {
    TodayView(viewModel: DashboardViewModel())
}
