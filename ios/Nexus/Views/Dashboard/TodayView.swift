import SwiftUI
import Combine

/// Canonical "Today" screen - frozen design, no customization
/// Shows: Recovery + Budget status, up to 3 ranked insights
struct TodayView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var offlineQueue = OfflineQueue.shared
    @State private var isFastingLoading = false
    @State private var fastingElapsed: String = "--:--"
    @State private var showingQuickLog = false

    private let fastingTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if !networkMonitor.isConnected {
                        TodayOfflineBanner(pendingCount: offlineQueue.pendingItemCount)
                    } else if offlineQueue.pendingItemCount > 0 {
                        TodaySyncingBanner(pendingCount: offlineQueue.pendingItemCount)
                    } else if viewModel.isFromCache && !viewModel.isForegroundRefreshing {
                        TodayCachedBanner(cacheAge: SyncCoordinator.shared.cacheAgeFormatted)
                    }

                    if viewModel.hasAnyStaleData && !viewModel.isForegroundRefreshing {
                        TodayStaleBanner(text: staleBannerText, onRefresh: viewModel.forceRefresh)
                    }

                    if let error = viewModel.errorMessage, viewModel.dashboardPayload == nil {
                        ErrorStateView(
                            message: error,
                            onRetry: viewModel.forceRefresh
                        )
                    } else if viewModel.dashboardPayload == nil && !viewModel.isLoading {
                        TodayNoDataView(onRefresh: viewModel.forceRefresh)
                    } else {
                        if let pendingMeal = viewModel.pendingMeals.first {
                            mealConfirmationSection(meal: pendingMeal)
                        }

                        // -- Status --
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

                        // -- Streaks --
                        StreakBadgesView(streaks: viewModel.dashboardPayload?.streaks)

                        // -- Nutrition + Fasting --
                        if hasNutritionData || viewModel.dashboardPayload?.fasting != nil {
                            VStack(spacing: 12) {
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

                        // -- Insights --
                        if !insightsEmpty {
                            todaySectionHeader("Insights")
                        }

                        InsightsFeedView(
                            insights: viewModel.dashboardPayload?.dailyInsights?.rankedInsights ?? [],
                            fallbackInsight: fallbackInsight
                        )
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .overlay(alignment: .top) {
                if viewModel.isForegroundRefreshing {
                    refreshingOverlay
                }
            }
            .background(Color.nexusBackground)
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView().scaleEffect(0.8)
                        }
                        Button(action: { showingQuickLog = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.nexusPrimary)
                        }
                        .accessibilityLabel("Quick Log")
                    }
                }
            }
            .sheet(isPresented: $showingQuickLog) {
                QuickLogView(viewModel: viewModel)
            }
            .onReceive(fastingTimer) { _ in updateFastingElapsed() }
            .onAppear { updateFastingElapsed() }
        }
    }

    // MARK: - Subviews

    private var refreshingOverlay: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Refreshing...").font(.caption.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.top, 8)
    }

    private func mealConfirmationSection(meal: InferredMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirm Meal").font(.headline).foregroundColor(.primary)
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
            } catch {}
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
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.top, 4)
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
