import SwiftUI

/// Main container view using the new Nexus Design System v2
/// Provides custom tab bar with center FAB and sidebar drawer navigation
struct ThemedContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var financeViewModel = FinanceViewModel()
    @StateObject private var receiptsViewModel = ReceiptsViewModel()
    @StateObject private var documentsViewModel = DocumentsViewModel()
    @ObservedObject private var quickActionManager = QuickActionManager.shared

    @State private var selectedTab = 0
    @State private var showSidebar = false
    @State private var showQuickLog = false

    // Navigation state for sidebar destinations
    @State private var showDocuments = false
    @State private var showMusic = false
    @State private var showReceipts = false
    @State private var showNotes = false
    @State private var showReminders = false
    @State private var showTraining = false
    @State private var showMedicationsSupplements = false
    @State private var showHomeControl = false
    @State private var showPipelineHealth = false
    @State private var showSettings = false
    @State private var showAppearance = false

    // Failed item alert state
    @State private var showingFailedItemAlert = false
    @State private var failedItemDescription = ""
    @State private var failedItemError = ""

    // Quick action feedback
    @State private var showingQuickActionFeedback = false
    @State private var quickActionTitle = ""
    @State private var quickActionBody = ""
    @State private var showingMoodSheet = false

    // Quick log specific sheets
    @State private var showWaterLog = false
    @State private var showFoodLog = false
    @State private var showExpenseLog = false

    var body: some View {
        ZStack {
            // Background
            NexusTheme.Colors.background
                .ignoresSafeArea()

            // Main content with tab views
            VStack(spacing: 0) {
                // Offline indicator
                OfflineBannerView()

                // Tab content
                TabView(selection: $selectedTab) {
                    // Tab 0: Home
                    NavigationStack {
                        ThemedTodayView(viewModel: viewModel, onMenuTap: openSidebar)
                    }
                    .tag(0)

                    // Tab 1: Health
                    NavigationStack {
                        ThemedHealthView(onMenuTap: openSidebar)
                    }
                    .tag(1)

                    // Tab 2: Finance
                    NavigationStack {
                        ThemedFinanceView(viewModel: financeViewModel, onMenuTap: openSidebar)
                    }
                    .tag(2)

                    // Tab 3: Calendar/Log
                    NavigationStack {
                        ThemedCalendarView(onMenuTap: openSidebar)
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environmentObject(viewModel)

                // Custom Tab Bar
                ThemeTabBar(selectedTab: $selectedTab) {
                    showQuickLog = true
                }
            }

            // Sidebar overlay
            ThemeSidebarDrawer(
                isOpen: $showSidebar,
                selectedTab: $selectedTab
            ) { destination in
                handleSidebarNavigation(destination)
            }
        }
        // Quick Log Sheet
        .sheet(isPresented: $showQuickLog) {
            ThemeQuickLogSheet { action in
                handleQuickLogAction(action)
            }
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
        // Sidebar destination sheets
        .sheet(isPresented: $showDocuments) {
            NavigationStack {
                DocumentsListView(viewModel: documentsViewModel)
            }
        }
        .sheet(isPresented: $showMusic) {
            NavigationStack {
                MusicView()
            }
        }
        .sheet(isPresented: $showReceipts) {
            NavigationStack {
                ReceiptsListView(viewModel: receiptsViewModel)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showNotes) {
            NavigationStack {
                NotesView()
            }
        }
        .sheet(isPresented: $showReminders) {
            NavigationStack {
                RemindersView()
            }
        }
        .sheet(isPresented: $showTraining) {
            NavigationStack {
                TrainingView()
            }
        }
        .sheet(isPresented: $showMedicationsSupplements) {
            NavigationStack {
                MedicationsSupplementsView()
            }
        }
        .sheet(isPresented: $showHomeControl) {
            NavigationStack {
                HomeControlView(viewModel: HomeViewModel.shared)
            }
        }
        .sheet(isPresented: $showPipelineHealth) {
            NavigationStack {
                PipelineHealthView()
            }
        }
        .sheet(isPresented: $showAppearance) {
            AppearanceSheet()
                .presentationDetents([.height(300)])
        }
        // Quick log action sheets
        .sheet(isPresented: $showWaterLog) {
            QuickWaterLogSheet()
        }
        .sheet(isPresented: $showFoodLog) {
            QuickFoodLogSheet()
        }
        .sheet(isPresented: $showingMoodSheet) {
            QuickMoodLogSheet()
        }
        .sheet(isPresented: $showExpenseLog) {
            QuickExpenseView(viewModel: financeViewModel)
        }
        // Notifications
        .onReceive(NotificationCenter.default.publisher(for: .offlineItemPermanentlyFailed)) { notification in
            if let description = notification.userInfo?["description"] as? String,
               let error = notification.userInfo?["error"] as? String {
                failedItemDescription = description
                failedItemError = error
                showingFailedItemAlert = true
            }
        }
        .alert("Sync Failed", isPresented: $showingFailedItemAlert) {
            Button("Review in Settings") {
                showSettings = true
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text("The following item failed to sync after multiple attempts:\n\n\"\(failedItemDescription)\"\n\nError: \(failedItemError)\n\nGo to Settings → Sync Status to retry or discard.")
        }
        // Quick action handling
        .onChange(of: quickActionManager.pendingAction) { _, action in
            guard let action = action else { return }
            handleQuickAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickActionCompleted)) { notification in
            if let title = notification.userInfo?["title"] as? String,
               let body = notification.userInfo?["body"] as? String {
                quickActionTitle = title
                quickActionBody = body
                showingQuickActionFeedback = true
            }
        }
        .alert(quickActionTitle, isPresented: $showingQuickActionFeedback) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(quickActionBody)
        }
    }

    // MARK: - Actions

    private func openSidebar() {
        withAnimation(NexusTheme.Animation.smooth) {
            showSidebar = true
        }
    }

    private func handleSidebarNavigation(_ destination: ThemeSidebarDrawer.SidebarDestination) {
        switch destination {
        case .documents:
            showDocuments = true
        case .receipts:
            showReceipts = true
        case .music:
            showMusic = true
        case .notes:
            showNotes = true
        case .reminders:
            showReminders = true
        case .training:
            showTraining = true
        case .medications:
            showMedicationsSupplements = true
        case .homeControl:
            showHomeControl = true
        case .pipelineHealth:
            showPipelineHealth = true
        case .settings:
            showSettings = true
        case .appearance:
            showAppearance = true
        }
    }

    private func handleQuickLogAction(_ action: ThemeQuickLogSheet.QuickLogAction) {
        switch action {
        case .water:
            showWaterLog = true
        case .food:
            showFoodLog = true
        case .mood:
            showingMoodSheet = true
        case .expense:
            showExpenseLog = true
        case .note:
            // TODO: Implement note logging
            break
        case .fasting:
            Task {
                await toggleFasting()
            }
        }
    }

    private func handleQuickAction(_ action: QuickActionManager.QuickActionType) {
        switch action {
        case .logWater, .startFast, .breakFast:
            Task {
                await quickActionManager.executePendingAction()
            }
        case .logMood:
            quickActionManager.pendingAction = nil
            showingMoodSheet = true
        }
    }

    private func toggleFasting() async {
        // Check current fasting state and toggle
        let isCurrentlyFasting = viewModel.dashboardPayload?.fasting?.isActive ?? false

        if isCurrentlyFasting {
            // Break fast
            do {
                let response = try await NexusAPI.shared.breakFast()
                if response.effectiveSuccess {
                    await viewModel.refresh()
                    NexusTheme.Haptics.success()
                }
            } catch {
                NexusTheme.Haptics.error()
            }
        } else {
            // Start fast
            do {
                let response = try await NexusAPI.shared.startFast()
                if response.effectiveSuccess {
                    await viewModel.refresh()
                    NexusTheme.Haptics.success()
                }
            } catch {
                NexusTheme.Haptics.error()
            }
        }
    }
}

// MARK: - Quick Water Log Sheet

struct QuickWaterLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.lg) {
            Capsule()
                .fill(NexusTheme.Colors.divider)
                .frame(width: 36, height: 5)
                .padding(.top, NexusTheme.Spacing.md)

            HStack {
                NexusTheme.Typography.cardTitle("Log Water")
                    .foregroundColor(NexusTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)

            VStack(spacing: NexusTheme.Spacing.xs) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 48))
                    .foregroundColor(NexusTheme.Colors.Semantic.blue)

                NexusTheme.Typography.metricLabel("Tap to log water")
                    .foregroundColor(NexusTheme.Colors.textSecondary)
            }
            .padding(.vertical, NexusTheme.Spacing.lg)

            Spacer()

            ThemePrimaryButton("Log Water", icon: "drop.fill", isLoading: isSubmitting) {
                submitWater()
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.bottom, NexusTheme.Spacing.xxxl)
        }
        .background(NexusTheme.Colors.card)
        .presentationDetents([.height(280)])
    }

    private func submitWater() {
        isSubmitting = true
        Task {
            do {
                let response = try await HabitsAPI.shared.logWater()
                await MainActor.run {
                    if response.success {
                        NexusTheme.Haptics.success()
                        dismiss()
                    } else {
                        NexusTheme.Haptics.error()
                        isSubmitting = false
                    }
                }
            } catch {
                await MainActor.run {
                    NexusTheme.Haptics.error()
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Quick Food Log Sheet

struct QuickFoodLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FoodSearchView { food in
                // Food selected - log it
                Task {
                    do {
                        _ = try await NexusAPI.shared.logFood(
                            food.name,
                            foodId: food.id,
                            mealType: nil
                        )
                        await MainActor.run {
                            NexusTheme.Haptics.success()
                            dismiss()
                        }
                    } catch {
                        await MainActor.run {
                            NexusTheme.Haptics.error()
                        }
                    }
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Placeholder Themed Views (to be implemented)

struct ThemedTodayView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onMenuTap: () -> Void

    var body: some View {
        // Wrap existing TodayView with themed header
        VStack(spacing: 0) {
            ThemePageHeader("Today", subtitle: formattedDate, onMenuTap: onMenuTap) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(NexusTheme.Colors.accent)
                }
            }

            TodayView(viewModel: viewModel)
        }
        .background(NexusTheme.Colors.background)
        .navigationBarHidden(true)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}

struct ThemedHealthView: View {
    let onMenuTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ThemePageHeader("Health", onMenuTap: onMenuTap)
            HealthFlatView()
        }
        .background(NexusTheme.Colors.background)
        .navigationBarHidden(true)
    }
}

struct ThemedFinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let onMenuTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ThemePageHeader("Finance", onMenuTap: onMenuTap)
            FinanceFlatView(viewModel: viewModel)
        }
        .background(NexusTheme.Colors.background)
        .navigationBarHidden(true)
    }
}

struct ThemedCalendarView: View {
    let onMenuTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ThemePageHeader("Calendar", onMenuTap: onMenuTap)
            CalendarView()
        }
        .background(NexusTheme.Colors.background)
        .navigationBarHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ThemedContentView()
        .environmentObject(AppSettings.shared)
}
