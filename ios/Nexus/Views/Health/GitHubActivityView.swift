import SwiftUI

struct GitHubActivityView: View {
    @StateObject private var coordinator = SyncCoordinator.shared

    private var activity: GitHubActivityWidget? {
        coordinator.dashboardPayload?.githubActivity
    }

    var body: some View {
        List {
            if let activity {
                summarySection(activity.summary)
                dailyActivitySection(activity.daily)
                reposSection(activity.repos)
            } else {
                Section {
                    NexusEmptyState(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "No GitHub Data",
                        message: "GitHub activity will appear here after your next dashboard sync."
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("GitHub Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private func summarySection(_ summary: GitHubSummary) -> some View {
        Section("Summary") {
            HStack(spacing: 16) {
                statBox(value: "\(summary.currentStreak)", label: "Streak", icon: "flame.fill", color: .orange)
                statBox(value: "\(summary.activeDays7d)", label: "Active (7d)", icon: "calendar", color: .nexusPrimary)
                statBox(value: "\(summary.pushEvents7d)", label: "Pushes (7d)", icon: "arrow.up.circle", color: .green)
            }
            .padding(.vertical, 4)

            HStack {
                Label("30-day active days", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(summary.activeDays30d)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                Label("30-day pushes", systemImage: "arrow.up.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(summary.pushEvents30d)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                Label("Max streak (90d)", systemImage: "flame")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(summary.maxStreak90d) days")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Daily Activity

    private func dailyActivitySection(_ daily: [GitHubDailyActivity]) -> some View {
        Section("Last 14 Days") {
            let maxPushes = daily.map(\.pushEvents).max() ?? 1

            ForEach(daily.suffix(14)) { day in
                HStack(spacing: 12) {
                    Text(formatDay(day.day))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)

                    GeometryReader { geo in
                        let fraction = maxPushes > 0 ? CGFloat(day.pushEvents) / CGFloat(maxPushes) : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.pushEvents > 0 ? Color.green : Color(.systemGray5))
                            .frame(width: max(fraction * geo.size.width, day.pushEvents > 0 ? 4 : geo.size.width), height: 14)
                    }
                    .frame(height: 14)

                    Text("\(day.pushEvents)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(day.pushEvents > 0 ? .primary : .secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Repos

    private func reposSection(_ repos: [GitHubRepo]) -> some View {
        Section("Active Repos") {
            if repos.isEmpty {
                Text("No recent repo activity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(repos) { repo in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Last active: \(formatDay(repo.lastActive))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(repo.events30d) events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDay(_ dateString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let date = df.date(from: dateString) else { return dateString }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }
}

#Preview {
    NavigationView {
        GitHubActivityView()
    }
}
