import SwiftUI

struct RecentLogsSection: View {
    let recentLogs: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)

                Spacer()

                if !recentLogs.isEmpty {
                    Text("\(recentLogs.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            if recentLogs.isEmpty {
                NexusEmptyState(
                    icon: "list.bullet.clipboard",
                    title: "No logs yet",
                    message: "Start tracking your day!\nUse the Log tab to add entries."
                )
                .frame(maxWidth: .infinity)
                .nexusCard()
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentLogs.prefix(8).enumerated()), id: \.element.id) { index, log in
                        EnhancedLogRow(entry: log)

                        if index < min(recentLogs.count - 1, 7) {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.nexusCardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Enhanced Log Row

struct EnhancedLogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colorForType(entry.type).opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: entry.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorForType(entry.type))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let calories = entry.calories {
                    Text("\(calories) cal")
                        .nexusChip(color: .nexusFood)
                }

                if let protein = entry.protein {
                    Text(String(format: "%.0fg", protein))
                        .nexusChip(color: .nexusProtein)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func colorForType(_ type: LogType) -> Color {
        ColorHelper.color(for: type)
    }
}

#Preview {
    RecentLogsSection(recentLogs: [])
}
