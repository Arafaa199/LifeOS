import SwiftUI
import EventKit
import os

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CalendarViewModel
    let event: CalendarDisplayEvent

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "calendarDetail")

    var body: some View {
        List {
            detailsSection
            if let notes = event.notes, !notes.isEmpty {
                notesSection(notes)
            }
            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEditSheet = true }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EventEditSheet(viewModel: viewModel, isPresented: $showingEditSheet, existingEvent: event)
        }
        .alert("Delete Event", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the event from your calendar. This cannot be undone.")
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Title", value: event.title)

            if event.isAllDay {
                LabeledContent("Date", value: formatDate(event.startAt))
                LabeledContent("All Day", value: "Yes")
            } else {
                LabeledContent("Start", value: formatDateTime(event.startAt))
                LabeledContent("End", value: formatDateTime(event.endAt))
                if !event.durationLabel.isEmpty {
                    LabeledContent("Duration", value: event.durationLabel)
                }
            }

            if let location = event.location, !location.isEmpty {
                LabeledContent {
                    Text(location)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Location", systemImage: "mappin")
                }
            }

            if let calendarName = event.calendarName, !calendarName.isEmpty {
                LabeledContent {
                    HStack {
                        Circle()
                            .fill(NexusTheme.Colors.accent)
                            .frame(width: 8, height: 8)
                        Text(calendarName)
                    }
                } label: {
                    Text("Calendar")
                }
            }
        }
    }

    // MARK: - Notes Section

    private func notesSection(_ notes: String) -> some View {
        Section("Notes") {
            Text(notes)
                .font(.body)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .tint(NexusTheme.Colors.Semantic.red)
                        Text("Deleting...")
                    } else {
                        Image(systemName: "trash")
                        Text("Delete Event")
                    }
                }
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - Actions

    private func deleteEvent() {
        isDeleting = true
        Task {
            do {
                try await viewModel.deleteEvent(eventId: event.eventId)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                logger.error("Failed to delete event: \(error.localizedDescription)")
                isDeleting = false
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        guard let date = parseISO8601(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDateTime(_ dateStr: String) -> String {
        guard let date = parseISO8601(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}

#Preview {
    NavigationView {
        EventDetailView(
            viewModel: CalendarViewModel(),
            event: CalendarDisplayEvent(
                eventId: "preview-1",
                title: "Team Meeting",
                startAt: "2026-02-07T10:00:00+04:00",
                endAt: "2026-02-07T11:00:00+04:00",
                isAllDay: false,
                calendarName: "Work",
                location: "Conference Room A",
                notes: "Discuss Q1 roadmap and planning"
            )
        )
    }
}
