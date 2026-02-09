import SwiftUI
import os

struct BJJView: View {
    @StateObject private var viewModel = BJJViewModel()
    @State private var showLogSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty {
                    errorView(error)
                } else if viewModel.sessions.isEmpty && viewModel.streak == nil {
                    emptyView
                } else {
                    contentView
                }
            }
            .navigationTitle("BJJ Training")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLogSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showLogSheet) {
                BJJLogSheet(viewModel: viewModel)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadInitialData()
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        List {
            // Streak Header
            if let streak = viewModel.streak {
                Section {
                    streakCard(streak)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Log Session Button
            Section {
                Button {
                    showLogSheet = true
                } label: {
                    Label("Log Training Session", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NexusTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: NexusTheme.Spacing.md, bottom: NexusTheme.Spacing.sm, trailing: NexusTheme.Spacing.md))
            }

            // Session History
            Section("Recent Sessions") {
                ForEach(viewModel.sessions) { session in
                    sessionRow(session)
                }

                // Load more
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load More") {
                                Task { await viewModel.loadMore() }
                            }
                            .foregroundColor(NexusTheme.Colors.accent)
                        }
                        Spacer()
                    }
                    .padding(.vertical, NexusTheme.Spacing.sm)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Streak Card

    private func streakCard(_ streak: BJJStreakInfo) -> some View {
        VStack(spacing: NexusTheme.Spacing.md) {
            // Main streak display
            HStack(spacing: NexusTheme.Spacing.lg) {
                // Flame with streak number
                VStack(spacing: NexusTheme.Spacing.xxs) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 72, height: 72)

                        VStack(spacing: 0) {
                            Text("🔥")
                                .font(.system(size: 28))
                            Text("\(streak.currentStreak)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }

                    Text("Week Streak")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                }

                Divider()
                    .frame(height: 60)

                // Stats
                VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
                    statRow(label: "This Week", value: "\(streak.sessionsThisWeek)", icon: "calendar")
                    statRow(label: "This Month", value: "\(streak.sessionsThisMonth)", icon: "calendar.badge.clock")
                    statRow(label: "Total", value: "\(streak.totalSessions)", icon: "trophy.fill")
                }

                Spacer()
            }

            // Longest streak badge
            if streak.longestStreak > streak.currentStreak {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        .font(.caption)
                    Text("Best: \(streak.longestStreak) week streak")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                }
            }
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
        .padding(.horizontal, NexusTheme.Spacing.md)
        .padding(.vertical, NexusTheme.Spacing.sm)
    }

    private func statRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: NexusTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(NexusTheme.Colors.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(NexusTheme.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(NexusTheme.Colors.textPrimary)
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: BJJSession) -> some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
            // Header: Date + Type Badge + Duration
            HStack {
                Text(formatDate(session.sessionDate))
                    .font(.subheadline.weight(.medium))

                sessionTypeBadge(session.sessionType)

                Spacer()

                Text(session.displayDuration)
                    .font(.subheadline)
                    .foregroundColor(NexusTheme.Colors.textSecondary)
            }

            // Strain (if available)
            if let strain = session.strain {
                HStack(spacing: NexusTheme.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(strainColor(strain))

                    Text("Strain \(String(format: "%.1f", strain))")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.textSecondary)

                    if let hr = session.hrAvg {
                        Text("•")
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                        Text("\(hr) bpm avg")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }

                    if let cal = session.calories {
                        Text("•")
                            .foregroundColor(NexusTheme.Colors.textTertiary)
                        Text("\(cal) cal")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
                }
            }

            // Techniques
            if let techniques = session.techniques, !techniques.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NexusTheme.Spacing.xxs) {
                        ForEach(techniques, id: \.self) { technique in
                            Text(technique)
                                .font(.caption2)
                                .padding(.horizontal, NexusTheme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(NexusTheme.Colors.accent.opacity(0.1))
                                .foregroundColor(NexusTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.textTertiary)
                    .lineLimit(2)
            }

            // Source indicator
            HStack(spacing: NexusTheme.Spacing.xxs) {
                Image(systemName: session.sourceIcon)
                    .font(.caption2)
                Text(session.sourceDisplayName)
                    .font(.caption2)
            }
            .foregroundColor(NexusTheme.Colors.textTertiary)
        }
        .padding(.vertical, NexusTheme.Spacing.xs)
    }

    private func sessionTypeBadge(_ type: String) -> some View {
        let (color, label) = sessionTypeInfo(type)
        return Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, NexusTheme.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func sessionTypeInfo(_ type: String) -> (Color, String) {
        switch type.lowercased() {
        case "bjj": return (NexusTheme.Colors.Semantic.blue, "BJJ")
        case "nogi": return (NexusTheme.Colors.Semantic.purple, "No-Gi")
        case "mma": return (NexusTheme.Colors.Semantic.red, "MMA")
        default: return (NexusTheme.Colors.textSecondary, type.uppercased())
        }
    }

    private func strainColor(_ strain: Double) -> Color {
        if strain >= 15 { return .red }
        if strain >= 10 { return .orange }
        return NexusTheme.Colors.Semantic.amber
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: NexusTheme.Spacing.md) {
            ProgressView()
            Text("Loading training history...")
                .font(.subheadline)
                .foregroundColor(NexusTheme.Colors.textSecondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Training Sessions", systemImage: "figure.martial.arts")
        } description: {
            Text("Start tracking your BJJ journey by logging your first session")
        } actions: {
            Button {
                showLogSheet = true
            } label: {
                Label("Log Session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    BJJView()
}
