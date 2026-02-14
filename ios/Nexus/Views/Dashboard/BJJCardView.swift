import SwiftUI
import os

/// Compact BJJ training card for dashboard - shows streak, sessions this week, last trained
struct BJJCardView: View {
    @StateObject private var viewModel = BJJViewModel()

    // Weekly target (configurable)
    private let weeklyTarget = 3

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.streak == nil {
                loadingCard
            } else if viewModel.streak != nil || !viewModel.sessions.isEmpty {
                contentCard
            }
            // Don't show anything if no data and not loading
        }
        .task {
            await viewModel.loadInitialData()
        }
    }

    // MARK: - Content Card

    private var contentCard: some View {
        NavigationLink(destination: BJJView()) {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.sm) {
                // Header row
                HStack(spacing: NexusTheme.Spacing.md) {
                    // Flame icon with streak
                    streakBadge

                    VStack(alignment: .leading, spacing: 2) {
                        // Primary text
                        Text(primaryText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)

                        // Secondary text
                        Text(secondaryText)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NexusTheme.Colors.textMuted)
                        .accessibilityHidden(true)
                }

                // Today's session highlight (if trained today)
                if let todaySession = todaySession {
                    todaySessionRow(todaySession)
                }
            }
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("BJJ Training, \(primaryText)")
    }

    // MARK: - Streak Badge

    private var streakBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: hasActiveStreak ? [.orange.opacity(0.2), .red.opacity(0.2)] : [NexusTheme.Colors.divider],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)

            VStack(spacing: -2) {
                Text("🔥")
                    .font(.system(size: 16))
                Text("\(viewModel.streak?.currentStreak ?? 0)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(hasActiveStreak ? .orange : NexusTheme.Colors.textTertiary)
            }
        }
        .accessibilityLabel("\(viewModel.streak?.currentStreak ?? 0) week streak")
    }

    // MARK: - Today Session Row

    private func todaySessionRow(_ session: BJJSession) -> some View {
        HStack(spacing: NexusTheme.Spacing.sm) {
            // Type badge
            Text(session.typeDisplayName)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sessionTypeColor(session.sessionType).opacity(0.15))
                .foregroundColor(sessionTypeColor(session.sessionType))
                .clipShape(Capsule())

            Text(session.displayDuration)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textPrimary)

            if let strain = session.strain {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                    Text(String(format: "%.1f", strain))
                        .font(.system(size: 11))
                }
                .foregroundColor(strainColor(strain))
            }

            Spacer()

            Text("Today")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(NexusTheme.Colors.Semantic.green)
        }
        .padding(.top, NexusTheme.Spacing.xs)
    }

    // MARK: - Computed Properties

    private var hasActiveStreak: Bool {
        (viewModel.streak?.currentStreak ?? 0) > 0
    }

    private var todaySession: BJJSession? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        return viewModel.sessions.first { $0.sessionDate == todayString }
    }

    private var primaryText: String {
        guard let streak = viewModel.streak else { return "BJJ Training" }

        let thisWeek = streak.sessionsThisWeek
        if thisWeek >= weeklyTarget {
            return "Goal hit! \(thisWeek) sessions"
        }
        return "\(thisWeek)/\(weeklyTarget) this week"
    }

    private var secondaryText: String {
        if let lastSession = viewModel.sessions.first {
            return "Last trained: \(relativeDate(lastSession.sessionDate))"
        }
        return "No sessions yet"
    }

    private func relativeDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            if days < 7 {
                return "\(days) days ago"
            } else if days < 14 {
                return "last week"
            } else {
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }

    private func sessionTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "bjj": return NexusTheme.Colors.Semantic.blue
        case "nogi": return NexusTheme.Colors.Semantic.purple
        case "mma": return NexusTheme.Colors.Semantic.red
        default: return NexusTheme.Colors.textSecondary
        }
    }

    private func strainColor(_ strain: Double) -> Color {
        if strain >= 15 { return .red }
        if strain >= 10 { return .orange }
        return NexusTheme.Colors.Semantic.amber
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(NexusTheme.Colors.divider)
                    .frame(width: 44, height: 44)
                ProgressView()
                    .scaleEffect(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("BJJ Training")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                Text("Loading...")
                    .font(.system(size: 11))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }

            Spacer()
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

#Preview {
    VStack(spacing: 16) {
        BJJCardView()
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
