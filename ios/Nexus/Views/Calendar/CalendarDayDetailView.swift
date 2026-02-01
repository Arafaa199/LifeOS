import SwiftUI

struct CalendarDayDetailView: View {
    let date: Date
    let events: [CalendarDisplayEvent]
    let reminders: [ReminderDisplayItem]

    private var allDayEvents: [CalendarDisplayEvent] {
        events.filter { $0.isAllDay }
    }

    private var timedEvents: [CalendarDisplayEvent] {
        events.filter { !$0.isAllDay }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if allDayEvents.isEmpty && timedEvents.isEmpty && reminders.isEmpty {
                        NexusEmptyState(
                            icon: "calendar",
                            title: "Nothing scheduled",
                            message: "No events or reminders for this day"
                        )
                    } else {
                        if !allDayEvents.isEmpty {
                            allDaySection
                        }

                        if !timedEvents.isEmpty {
                            eventsSection
                        }

                        if !reminders.isEmpty {
                            remindersSection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - All-Day Events

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL DAY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(allDayEvents) { event in
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .nexusChip(color: .nexusPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timed Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EVENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(timedEvents) { event in
                eventRow(event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ event: CalendarDisplayEvent) -> some View {
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

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMINDERS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(reminders) { reminder in
                reminderRow(reminder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderRow(_ reminder: ReminderDisplayItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundColor(reminder.isCompleted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(reminder.title ?? "Untitled")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .strikethrough(reminder.isCompleted)
                        .foregroundColor(reminder.isCompleted ? .secondary : .primary)

                    if let priority = reminder.priorityLabel {
                        Text(priority)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let time = reminder.dueTime {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let listName = reminder.listName {
                        Text(listName)
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .nexusCard()
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }
}
