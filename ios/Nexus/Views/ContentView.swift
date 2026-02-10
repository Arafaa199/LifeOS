import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var financeViewModel = FinanceViewModel()
    @ObservedObject private var quickActionManager = QuickActionManager.shared
    @State private var selectedTab = 0

    // Failed item alert state
    @State private var showingFailedItemAlert = false
    @State private var failedItemDescription = ""
    @State private var failedItemError = ""

    // Quick action feedback
    @State private var showingQuickActionFeedback = false
    @State private var quickActionTitle = ""
    @State private var quickActionBody = ""
    @State private var showingMoodSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Sync conflict notification at the top
            ConflictBannerView()

            // Offline indicator
            OfflineBannerView()

            TabView(selection: $selectedTab) {
                TodayView(viewModel: viewModel)
                    .tabItem {
                        Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house")
                    }
                    .tag(0)

                HealthFlatView()
                    .tabItem {
                        Label("Health", systemImage: selectedTab == 1 ? "heart.fill" : "heart")
                    }
                    .tag(1)

                FinanceFlatView(viewModel: financeViewModel)
                    .tabItem {
                        Label("Finance", systemImage: selectedTab == 2 ? "chart.pie.fill" : "chart.pie")
                    }
                    .tag(2)

                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: selectedTab == 3 ? "calendar.circle.fill" : "calendar.circle")
                    }
                    .tag(3)

                MoreView()
                    .tabItem {
                        Label("More", systemImage: selectedTab == 4 ? "ellipsis.circle.fill" : "ellipsis.circle")
                    }
                    .tag(4)
            }
            .tint(NexusTheme.Colors.accent)
            .environmentObject(viewModel)
        }
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
                selectedTab = 4  // More tab (Settings is inside)
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The following item failed to sync after multiple attempts:")
                    .fontWeight(.medium)

                Text("\"\(failedItemDescription)\"")
                    .italic()

                Text("Error:")
                    .fontWeight(.medium)
                    .padding(.top, 4)

                Text(failedItemError)
                    .font(.caption)

                Text("Go to More → Settings → Sync Status to retry or discard this item.")
                    .padding(.top, 4)
            }
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
        .sheet(isPresented: $showingMoodSheet) {
            QuickMoodLogSheet()
        }
    }

    private func handleQuickAction(_ action: QuickActionManager.QuickActionType) {
        switch action {
        case .logWater, .startFast, .breakFast:
            // Execute in background - feedback via notification
            Task {
                await quickActionManager.executePendingAction()
            }
        case .logMood:
            // Show mood input sheet
            quickActionManager.pendingAction = nil
            showingMoodSheet = true
        }
    }
}

// MARK: - Quick Mood Log Sheet

struct QuickMoodLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var moodScore: Double = 5
    @State private var energyLevel: Double = 5
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mood: \(Int(moodScore))/10")
                            .font(.headline)
                        Slider(value: $moodScore, in: 1...10, step: 1)
                            .tint(NexusTheme.Colors.accent)
                    }
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Energy: \(Int(energyLevel))/10")
                            .font(.headline)
                        Slider(value: $energyLevel, in: 1...10, step: 1)
                            .tint(NexusTheme.Colors.accent)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("How are you feeling?")
                }
            }
            .navigationTitle("Log Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        submitMood()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submitMood() {
        isSubmitting = true
        Task {
            do {
                let response = try await NexusAPI.shared.logMood(
                    mood: Int(moodScore),
                    energy: Int(energyLevel),
                    notes: nil
                )
                await MainActor.run {
                    if response.success {
                        NotificationCenter.default.post(
                            name: .quickActionCompleted,
                            object: nil,
                            userInfo: ["title": "Mood Logged", "body": "Mood \(Int(moodScore))/10, Energy \(Int(energyLevel))/10"]
                        )
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings.shared)
}
