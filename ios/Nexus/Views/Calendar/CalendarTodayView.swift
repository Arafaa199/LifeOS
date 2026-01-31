import SwiftUI

struct CalendarTodayView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard

                if !viewModel.allDayEvents.isEmpty {
                    allDaySection
                }

                if viewModel.isLoadingEvents {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = viewModel.errorMessage {
                    NexusEmptyState(
                        icon: "exclamationmark.triangle",
                        title: "Failed to load",
                        message: error,
                        actionTitle: "Retry"
                    ) {
                        Task { await viewModel.fetchTodayEvents() }
                    }
                } else if viewModel.todayEvents.isEmpty && viewModel.allDayEvents.isEmpty {
                    NexusEmptyState(
                        icon: "calendar",
                        title: "No events",
                        message: "No calendar events for today"
                    )
                } else {
                    eventsTimeline
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedToday)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let summary = viewModel.calendarSummary {
                    Text("\(summary.meetingCount) event\(summary.meetingCount == 1 ? "" : "s")")
                        .font(.title2)
                        .fontWeight(.semibold)
                } else {
                    Text("\(viewModel.events.count) event\(viewModel.events.count == 1 ? "" : "s")")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }

            Spacer()

            if let summary = viewModel.calendarSummary, summary.meetingHours > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1fh", summary.meetingHours))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.nexusPrimary)
                    Text("in meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .nexusCard()
    }

    // MARK: - All-Day Events

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL DAY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(viewModel.allDayEvents) { event in
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .nexusChip(color: .nexusPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Events Timeline

    private var eventsTimeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.todayEvents.enumerated()), id: \.element.id) { index, event in
                eventRow(event, isLast: index == viewModel.todayEvents.count - 1)
            }
        }
    }

    private func eventRow(_ event: CalendarDisplayEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(event.startTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .trailing)

                if !isLast {
                    Rectangle()
                        .fill(Color.nexusPrimary.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(event.startTime) – \(event.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.caption2)
                            .foregroundColor(.nexusPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.nexusPrimary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                        Text(location)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if let calendarName = event.calendarName, !calendarName.isEmpty {
                    Text(calendarName)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexusCard()
        }
        .padding(.bottom, 4)
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}
