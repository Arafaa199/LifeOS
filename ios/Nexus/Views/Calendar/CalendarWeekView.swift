import SwiftUI

struct CalendarWeekView: View {
    @ObservedObject var viewModel: CalendarViewModel

    private var groupedByDay: [(String, [CalendarDisplayEvent])] {
        let grouped = Dictionary(grouping: viewModel.events) { event in
            String(event.startAt.prefix(10))
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                        Task { await viewModel.fetchWeekEvents() }
                    }
                } else if viewModel.events.isEmpty {
                    NexusEmptyState(
                        icon: "calendar",
                        title: "No events",
                        message: "No calendar events this week"
                    )
                } else {
                    ForEach(groupedByDay, id: \.0) { day, dayEvents in
                        daySection(day: day, dayEvents: dayEvents)
                    }
                }
            }
            .padding()
        }
    }

    private func daySection(day: String, dayEvents: [CalendarDisplayEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatDayHeader(day))
                .font(.headline)
                .foregroundColor(.primary)

            ForEach(dayEvents) { event in
                HStack(spacing: 12) {
                    if event.isAllDay {
                        Text("All day")
                            .font(.caption)
                            .foregroundColor(.nexusPrimary)
                            .frame(width: 48, alignment: .trailing)
                    } else {
                        Text(event.startTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if !event.isAllDay {
                            Text("\(event.startTime) – \(event.endTime)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.caption2)
                            .foregroundColor(.nexusPrimary)
                    }
                }
                .nexusCard()
            }
        }
    }

    private func formatDayHeader(_ dateString: String) -> String {
        let inputFmt = DateFormatter()
        inputFmt.dateFormat = "yyyy-MM-dd"
        inputFmt.locale = Locale(identifier: "en_US_POSIX")

        guard let date = inputFmt.date(from: dateString) else { return dateString }

        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }

        let outputFmt = DateFormatter()
        outputFmt.dateFormat = "EEEE, MMM d"
        return outputFmt.string(from: date)
    }
}
