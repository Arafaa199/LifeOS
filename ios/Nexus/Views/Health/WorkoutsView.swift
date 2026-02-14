import SwiftUI
import HealthKit
import os

struct WorkoutsView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var workouts: [Workout] = []
    @State private var weeklyStats: WeeklyWorkoutStats?
    @State private var whoopToday: WhoopDayStrain?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var isSyncing = false
    @State private var searchText = ""

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "workouts")

    private var filteredWorkouts: [Workout] {
        if searchText.isEmpty {
            return workouts
        }
        return workouts.filter { workout in
            let nameMatch = (workout.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            let typeMatch = workout.typeDisplayName.localizedCaseInsensitiveContains(searchText)
            return nameMatch || typeMatch
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ThemeLoadingView(message: "Loading workouts...")
            } else if let error = errorMessage {
                errorView(error)
            } else {
                workoutsList
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: syncFromHealthKit) {
                        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                    }
                    .disabled(isSyncing)

                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddWorkoutSheet { _ in
                Task { await loadWorkouts() }
            }
        }
        .refreshable {
            await loadWorkouts()
        }
        .task {
            await loadWorkouts()
        }
    }

    // MARK: - Workouts List

    private var workoutsList: some View {
        List {
            // Weekly Summary (only show when not searching)
            if searchText.isEmpty, let stats = weeklyStats {
                Section {
                    weeklySummaryCard(stats)
                }
            }

            // WHOOP Today (only show when not searching)
            if searchText.isEmpty, let whoop = whoopToday, whoop.dayStrain != nil {
                Section("Today's Strain (WHOOP)") {
                    whoopCard(whoop)
                }
            }

            // Recent Workouts
            if workouts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.run",
                        description: Text("Sync from Apple Watch or add manually")
                    )
                }
            } else if filteredWorkouts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No workouts match your search")
                    )
                }
            } else {
                Section("Recent") {
                    ForEach(filteredWorkouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search workouts")
    }

    // MARK: - Weekly Summary

    private func weeklySummaryCard(_ stats: WeeklyWorkoutStats) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                Text("\(stats.workoutCount) workouts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                statItem(
                    icon: "clock.fill",
                    value: formatDuration(stats.totalDuration),
                    label: "Duration",
                    color: .blue
                )

                statItem(
                    icon: "flame.fill",
                    value: "\(stats.totalCalories)",
                    label: "Calories",
                    color: .orange
                )

                if stats.avgStrain > 0 {
                    statItem(
                        icon: "bolt.heart.fill",
                        value: String(format: "%.1f", stats.avgStrain),
                        label: "Avg Strain",
                        color: .purple
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.headline)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - WHOOP Card

    private func whoopCard(_ whoop: WhoopDayStrain) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "heart.circle.fill")
                        .foregroundColor(NexusTheme.Colors.Semantic.red)
                    Text("Day Strain")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let strain = whoop.dayStrain {
                    Text(String(format: "%.1f", strain))
                        .font(.title.bold())
                        .foregroundColor(strainColor(strain))
                }
            }

            Spacer()

            if let avgHr = whoop.avgHr {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(avgHr) bpm")
                        .font(.headline)
                }
            }

            if let maxHr = whoop.maxHr {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Max HR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(maxHr) bpm")
                        .font(.headline)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await loadWorkouts() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func strainColor(_ strain: Double) -> Color {
        if strain >= 18 { return .red }
        if strain >= 14 { return .orange }
        if strain >= 10 { return .yellow }
        return .green
    }

    // MARK: - API

    private func loadWorkouts() async {
        isLoading = workouts.isEmpty
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchWorkouts()
            workouts = response.workouts
            weeklyStats = response.weeklyStats
            whoopToday = response.whoopToday
            logger.info("Loaded \(response.workouts.count) workouts")
        } catch {
            if workouts.isEmpty {
                errorMessage = error.localizedDescription
            }
            logger.error("Failed to load workouts: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func syncFromHealthKit() {
        isSyncing = true
        Task {
            await healthKitManager.syncWorkouts()
            await loadWorkouts()
            isSyncing = false
        }
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                Circle()
                    .fill(NexusTheme.Colors.accent.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: workout.typeIcon)
                    .font(.system(size: 18))
                    .foregroundColor(NexusTheme.Colors.accent)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workout.name ?? workout.typeDisplayName)
                        .font(.body)

                    Spacer()

                    if let source = workout.source {
                        Image(systemName: workout.sourceIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    if !workout.displayDuration.isEmpty {
                        Label(workout.displayDuration, systemImage: "clock")
                    }

                    if let calories = workout.caloriesBurned {
                        Label("\(calories) cal", systemImage: "flame")
                    }

                    if let strain = workout.strain {
                        Label(String(format: "%.1f", strain), systemImage: "bolt.heart")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        WorkoutsView()
    }
}
