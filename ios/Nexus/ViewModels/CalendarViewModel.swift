import SwiftUI
import Combine
import os

@MainActor
class CalendarViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "calendar")
    @Published var calendarSummary: CalendarSummary?
    @Published var events: [CalendarDisplayEvent] = []
    @Published var isLoadingEvents = false
    @Published var errorMessage: String?

    // Month/Year support
    @Published var monthEvents: [String: [CalendarDisplayEvent]] = [:]
    @Published var monthReminders: [String: [ReminderDisplayItem]] = [:]
    @Published var selectedDate: Date?
    @Published var yearEventCounts: [String: Int] = [:]
    @Published var yearReminderCounts: [String: Int] = [:]

    private let api = NexusAPI.shared
    private let coordinator = SyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var isLoading: Bool {
        isLoadingEvents || coordinator.domainStates[.dashboard]?.isSyncing == true
    }

    var todayEvents: [CalendarDisplayEvent] {
        events.filter { !$0.isAllDay }.sorted { $0.startAt < $1.startAt }
    }

    var allDayEvents: [CalendarDisplayEvent] {
        events.filter { $0.isAllDay }
    }

    init() {
        coordinator.$dashboardPayload
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.calendarSummary = payload.calendarSummary
            }
            .store(in: &cancellables)

        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func loadData() async {
        await fetchTodayEvents()
    }

    func fetchTodayEvents() async {
        isLoadingEvents = true
        errorMessage = nil

        let today = Self.dayKeyFormatter.string(from: Date())

        do {
            let response: CalendarDisplayEventsResponse = try await api.get(
                "/webhook/nexus-calendar-events?start=\(today)&end=\(today)"
            )
            if response.success {
                events = response.events ?? []
            } else {
                events = []
                errorMessage = "Failed to load calendar events"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingEvents = false
    }

    func fetchWeekEvents() async {
        isLoadingEvents = true
        errorMessage = nil

        let today = Date()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: today) ?? today

        do {
            let response: CalendarDisplayEventsResponse = try await api.get(
                "/webhook/nexus-calendar-events?start=\(Self.dayKeyFormatter.string(from: today))&end=\(Self.dayKeyFormatter.string(from: weekEnd))"
            )
            if response.success {
                events = response.events ?? []
            } else {
                events = []
                errorMessage = "Failed to load calendar events"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingEvents = false
    }

    // MARK: - Month Events

    func fetchMonthEvents(year: Int, month: Int) async {
        isLoadingEvents = true
        errorMessage = nil

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1

        guard let startDate = Calendar.current.date(from: comps),
              let endDate = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
            isLoadingEvents = false
            return
        }

        let startStr = Self.dayKeyFormatter.string(from: startDate)
        let endStr = Self.dayKeyFormatter.string(from: endDate)

        do {
            let response: CalendarDisplayEventsResponse = try await api.get(
                "/webhook/nexus-calendar-events?start=\(startStr)&end=\(endStr)"
            )
            if response.success {
                let allEvents = response.events ?? []
                var grouped: [String: [CalendarDisplayEvent]] = [:]
                for event in allEvents {
                    let dayKey = String(event.startAt.prefix(10))
                    grouped[dayKey, default: []].append(event)
                }
                monthEvents = grouped
            } else {
                monthEvents = [:]
                errorMessage = "Failed to load calendar events"
            }
        } catch {
            errorMessage = error.localizedDescription
            monthEvents = [:]
        }

        isLoadingEvents = false
    }

    // MARK: - Reminders

    func fetchReminders(start: String, end: String) async {
        do {
            let response: RemindersDisplayResponse = try await api.get(
                "/webhook/nexus-reminders?start=\(start)&end=\(end)"
            )
            if response.success {
                var grouped: [String: [ReminderDisplayItem]] = [:]
                for reminder in response.reminders ?? [] {
                    let dayKey: String
                    if let dueDate = reminder.dueDate {
                        dayKey = String(dueDate.prefix(10))
                    } else {
                        dayKey = "no_date"
                    }
                    grouped[dayKey, default: []].append(reminder)
                }
                monthReminders = grouped
            }
        } catch {
            logger.error("Failed to fetch reminders: \(error.localizedDescription)")
        }
    }

    // MARK: - Year Events (counts only)

    func fetchYearEvents(year: Int) async {
        isLoadingEvents = true

        let startStr = "\(year)-01-01"
        let endStr = "\(year)-12-31"

        async let eventsTask: Void = {
            do {
                let response: CalendarDisplayEventsResponse = try await self.api.get(
                    "/webhook/nexus-calendar-events?start=\(startStr)&end=\(endStr)"
                )
                if response.success {
                    var counts: [String: Int] = [:]
                    for event in response.events ?? [] {
                        let dayKey = String(event.startAt.prefix(10))
                        counts[dayKey, default: 0] += 1
                    }
                    await MainActor.run { self.yearEventCounts = counts }
                }
            } catch {
                await MainActor.run { self.logger.error("Failed to fetch year events: \(error.localizedDescription)") }
            }
        }()

        async let remindersTask: Void = {
            do {
                let response: RemindersDisplayResponse = try await self.api.get(
                    "/webhook/nexus-reminders?start=\(startStr)&end=\(endStr)"
                )
                if response.success {
                    var counts: [String: Int] = [:]
                    for reminder in response.reminders ?? [] {
                        if let dueDate = reminder.dueDate {
                            let dayKey = String(dueDate.prefix(10))
                            counts[dayKey, default: 0] += 1
                        }
                    }
                    await MainActor.run { self.yearReminderCounts = counts }
                }
            } catch {
                await MainActor.run { self.logger.error("Failed to fetch year reminders: \(error.localizedDescription)") }
            }
        }()

        _ = await (eventsTask, remindersTask)
        isLoadingEvents = false
    }

    // MARK: - CRUD Operations

    func createEvent(title: String, startAt: Date, endAt: Date, isAllDay: Bool = false, calendarName: String? = nil, location: String? = nil, notes: String? = nil) async throws {
        errorMessage = nil
        do {
            _ = try await CalendarSyncService.shared.createEvent(
                title: title,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                calendarName: calendarName,
                location: location,
                notes: notes
            )
            // Refresh the current month view
            if let selected = selectedDate {
                let year = Calendar.current.component(.year, from: selected)
                let month = Calendar.current.component(.month, from: selected)
                await fetchMonthEvents(year: year, month: month)
            }
            logger.info("Created event: \(title)")
        } catch {
            logger.error("Failed to create event: \(error.localizedDescription)")
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            throw error
        }
    }

    func updateEvent(eventId: String, title: String? = nil, startAt: Date? = nil, endAt: Date? = nil, isAllDay: Bool? = nil, location: String? = nil, notes: String? = nil) async throws {
        errorMessage = nil
        do {
            // Find the EKEvent in EventKit
            let events = CalendarSyncService.shared.fetchEvents()
            guard let ekEvent = events.first(where: { $0.eventIdentifier == eventId }) else {
                throw APIError.custom("Event not found in calendar")
            }

            try await CalendarSyncService.shared.updateEvent(
                ekEvent,
                title: title,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                location: location,
                notes: notes
            )

            // Refresh the current month view
            if let selected = selectedDate {
                let year = Calendar.current.component(.year, from: selected)
                let month = Calendar.current.component(.month, from: selected)
                await fetchMonthEvents(year: year, month: month)
            }
            logger.info("Updated event: \(eventId)")
        } catch {
            logger.error("Failed to update event: \(error.localizedDescription)")
            errorMessage = "Failed to update event: \(error.localizedDescription)"
            throw error
        }
    }

    func deleteEvent(eventId: String) async throws {
        errorMessage = nil
        do {
            try await CalendarSyncService.shared.deleteEventById(eventId)

            // Refresh the current month view
            if let selected = selectedDate {
                let year = Calendar.current.component(.year, from: selected)
                let month = Calendar.current.component(.month, from: selected)
                await fetchMonthEvents(year: year, month: month)
            }
            logger.info("Deleted event: \(eventId)")
        } catch {
            logger.error("Failed to delete event: \(error.localizedDescription)")
            errorMessage = "Failed to delete event: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Helpers

    func eventsForDate(_ date: Date) -> [CalendarDisplayEvent] {
        let key = Self.dayKeyFormatter.string(from: date)
        return (monthEvents[key] ?? []).sorted { $0.startAt < $1.startAt }
    }

    func remindersForDate(_ date: Date) -> [ReminderDisplayItem] {
        let key = Self.dayKeyFormatter.string(from: date)
        return monthReminders[key] ?? []
    }
}

// MARK: - Calendar Display Event Model (distinct from CalendarSyncService.CalendarEvent)

struct CalendarDisplayEvent: Codable, Identifiable {
    var id: String { eventId }

    let eventId: String
    let title: String
    let startAt: String
    let endAt: String
    let isAllDay: Bool
    let calendarName: String?
    let location: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case calendarName = "calendar_name"
        case location
        case notes
    }

    init(eventId: String, title: String, startAt: String, endAt: String, isAllDay: Bool, calendarName: String?, location: String?, notes: String?) {
        self.eventId = eventId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.location = location
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decode(String.self, forKey: .startAt)
        endAt = try container.decode(String.self, forKey: .endAt)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        calendarName = try container.decodeIfPresent(String.self, forKey: .calendarName)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    var startTime: String {
        guard let range = startAt.range(of: "T") else { return startAt }
        let time = String(startAt[range.upperBound...])
        return String(time.prefix(5))
    }

    var endTime: String {
        guard let range = endAt.range(of: "T") else { return endAt }
        let time = String(endAt[range.upperBound...])
        return String(time.prefix(5))
    }

    var durationMinutes: Int? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let start = fmt.date(from: startAt),
              let end = fmt.date(from: endAt) else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    var durationLabel: String {
        guard let mins = durationMinutes else { return "" }
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

struct CalendarDisplayEventsResponse: Codable {
    let success: Bool
    let events: [CalendarDisplayEvent]?
    let count: Int?
}

// MARK: - Reminder Display Model

struct ReminderDisplayItem: Codable, Identifiable {
    var id: String { reminderId }

    let reminderId: String
    let title: String?
    let notes: String?
    let dueDate: String?
    let isCompleted: Bool
    let completedDate: String?
    let priority: Int
    let listName: String?

    enum CodingKeys: String, CodingKey {
        case reminderId = "reminder_id"
        case title
        case notes
        case dueDate = "due_date"
        case isCompleted = "is_completed"
        case completedDate = "completed_date"
        case priority
        case listName = "list_name"
    }

    var dueTime: String? {
        guard let dueDate, let range = dueDate.range(of: "T") else { return nil }
        let time = String(dueDate[range.upperBound...])
        let hhmm = String(time.prefix(5))
        return hhmm == "00:00" ? nil : hhmm
    }

    var priorityLabel: String? {
        switch priority {
        case 1: return "!!!"
        case 5: return "!!"
        case 9: return "!"
        default: return nil
        }
    }
}

struct RemindersDisplayResponse: Codable {
    let success: Bool
    let reminders: [ReminderDisplayItem]?
    let count: Int?
}
