import SwiftUI
import Combine

@MainActor
class CalendarViewModel: ObservableObject {
    @Published var calendarSummary: CalendarSummary?
    @Published var events: [CalendarDisplayEvent] = []
    @Published var isLoadingEvents = false
    @Published var errorMessage: String?

    private let api = NexusAPI.shared
    private let coordinator = SyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        do {
            let response: CalendarDisplayEventsResponse = try await api.get(
                "/webhook/nexus-calendar-events?start=\(today)&end=\(today)"
            )
            if response.success {
                events = response.events ?? []
            } else {
                events = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingEvents = false
    }

    func fetchWeekEvents() async {
        isLoadingEvents = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: today) ?? today

        do {
            let response: CalendarDisplayEventsResponse = try await api.get(
                "/webhook/nexus-calendar-events?start=\(formatter.string(from: today))&end=\(formatter.string(from: weekEnd))"
            )
            if response.success {
                events = response.events ?? []
            } else {
                events = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingEvents = false
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
