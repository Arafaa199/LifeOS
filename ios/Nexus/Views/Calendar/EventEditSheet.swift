import SwiftUI
import EventKit
import UIKit
import os

struct EventEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var isPresented: Bool
    let existingEvent: CalendarDisplayEvent?

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedCalendarTitle: String = ""

    @State private var availableCalendars: [EKCalendar] = []
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "eventEdit")
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let notificationHaptics = UINotificationFeedbackGenerator()

    var isEditing: Bool { existingEvent != nil }

    var body: some View {
        NavigationView {
            Form {
                eventDetailsSection
                dateTimeSection
                locationSection
                notesSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.nexusBackground)
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveEvent()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .onAppear {
                loadCalendars()
                if let event = existingEvent {
                    populateFromExisting(event)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    // MARK: - Form Sections

    private var eventDetailsSection: some View {
        Section("Event Details") {
            TextField("Title", text: $title)
                .textContentType(.none)

            if !availableCalendars.isEmpty {
                Picker("Calendar", selection: $selectedCalendarTitle) {
                    ForEach(availableCalendars, id: \.title) { calendar in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                        }
                        .tag(calendar.title)
                    }
                }
            }
        }
    }

    private var dateTimeSection: some View {
        Section("Date & Time") {
            Toggle("All Day", isOn: $isAllDay)

            if isAllDay {
                DatePicker("Date", selection: $startDate, displayedComponents: .date)
            } else {
                DatePicker("Start", selection: $startDate)
                    .onChange(of: startDate) { newValue in
                        if endDate <= newValue {
                            endDate = newValue.addingTimeInterval(3600)
                        }
                    }

                DatePicker("End", selection: $endDate)
            }

            if !isAllDay {
                let duration = endDate.timeIntervalSince(startDate)
                let hours = Int(duration) / 3600
                let minutes = (Int(duration) % 3600) / 60
                let durationText = hours > 0
                    ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h")
                    : "\(minutes)m"

                LabeledContent("Duration", value: durationText)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            TextField("Add Location", text: $location)
                .textContentType(.fullStreetAddress)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
        }
    }

    // MARK: - Actions

    private func loadCalendars() {
        availableCalendars = CalendarSyncService.shared.availableCalendars()
        if selectedCalendarTitle.isEmpty, let defaultCal = CalendarSyncService.shared.eventStore.defaultCalendarForNewEvents {
            selectedCalendarTitle = defaultCal.title
        }
    }

    private func populateFromExisting(_ event: CalendarDisplayEvent) {
        title = event.title
        isAllDay = event.isAllDay
        location = event.location ?? ""
        notes = event.notes ?? ""
        selectedCalendarTitle = event.calendarName ?? ""

        if let start = parseISO8601(event.startAt) {
            startDate = start
        }
        if let end = parseISO8601(event.endAt) {
            endDate = end
        }
    }

    private func saveEvent() {
        guard !title.isEmpty else { return }

        haptics.impactOccurred()
        isSaving = true

        Task {
            do {
                if let existing = existingEvent {
                    try await viewModel.updateEvent(
                        eventId: existing.eventId,
                        title: title,
                        startAt: startDate,
                        endAt: isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: startDate)! : endDate,
                        isAllDay: isAllDay,
                        location: location.isEmpty ? nil : location,
                        notes: notes.isEmpty ? nil : notes
                    )
                } else {
                    try await viewModel.createEvent(
                        title: title,
                        startAt: startDate,
                        endAt: isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: startDate)! : endDate,
                        isAllDay: isAllDay,
                        calendarName: selectedCalendarTitle.isEmpty ? nil : selectedCalendarTitle,
                        location: location.isEmpty ? nil : location,
                        notes: notes.isEmpty ? nil : notes
                    )
                }

                await MainActor.run {
                    notificationHaptics.notificationOccurred(.success)
                    isPresented = false
                }
            } catch {
                logger.error("Failed to save event: \(error.localizedDescription)")
                await MainActor.run {
                    notificationHaptics.notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}

#Preview("New Event") {
    EventEditSheet(
        viewModel: CalendarViewModel(),
        isPresented: .constant(true),
        existingEvent: nil
    )
}

#Preview("Edit Event") {
    EventEditSheet(
        viewModel: CalendarViewModel(),
        isPresented: .constant(true),
        existingEvent: CalendarDisplayEvent(
            eventId: "preview-1",
            title: "Team Meeting",
            startAt: "2026-02-07T10:00:00+04:00",
            endAt: "2026-02-07T11:00:00+04:00",
            isAllDay: false,
            calendarName: "Work",
            location: "Conference Room A",
            notes: "Discuss Q1 roadmap"
        )
    )
}
