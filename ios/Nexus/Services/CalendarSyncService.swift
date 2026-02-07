import Foundation
import EventKit
import UIKit
import Combine
import os

@MainActor
class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "calendarSync")

    let eventStore = EKEventStore()

    @Published var lastSyncDate: Date?
    @Published var lastSyncEventCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "calendar_last_sync_date"
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = Constants.Dubai.timeZone
        return f
    }()

    private init() {
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                updateAuthorizationStatus()
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                updateAuthorizationStatus()
                return granted
            }
        } catch {
            logger.error("[CalendarSync] Access request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Main Sync Entry Point (6-step bidirectional diff)

    func syncAllData() async throws {
        guard !isSyncing else { return }

        updateAuthorizationStatus()
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else {
            logger.warning("[CalendarSync] Not authorized to access calendar")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Step 1: PULL from EventKit
        let ekEvents = fetchEvents()
        let ekMap: [String: EKEvent] = Dictionary(
            uniqueKeysWithValues: ekEvents.compactMap { event in
                guard let id = event.eventIdentifier else { return nil }
                return (id, event)
            }
        )

        // Step 2: PULL from DB
        let dbState = try await fetchSyncState()
        let dbMap = Dictionary(dbState.map { ($0.event_id, $0) }, uniquingKeysWith: { first, _ in first })

        var upsertPayloads: [CalendarEventPayload] = []
        var confirmations: [CalendarSyncConfirmation] = []

        // Step 3: DIFF — compare EK events against DB
        for (ekId, ekEvent) in ekMap {
            let payload = makePayload(from: ekEvent)

            if let dbRow = dbMap[ekId] {
                if dbRow.sync_status == "pending_push" {
                    // Conflict: DB has pending changes. Last-writer-wins by timestamp.
                    if let ekMod = ekEvent.lastModifiedDate,
                       let dbMod = dbRow.updated_at,
                       ekMod > dbMod {
                        upsertPayloads.append(payload)
                    }
                    // else: DB wins, will push in step 5
                } else if dbRow.sync_status == "synced" {
                    if let ekMod = ekEvent.lastModifiedDate,
                       let dbEkMod = dbRow.eventkit_modified_at {
                        if ekMod > dbEkMod {
                            upsertPayloads.append(payload)
                        }
                        // else: equal = our own echo, skip
                    } else {
                        upsertPayloads.append(payload)
                    }
                }
            } else {
                // New remote event, not in DB
                upsertPayloads.append(payload)
            }
        }

        // Step 3 continued: Send diff-aware upsert to DB (includes absence detection)
        if !upsertPayloads.isEmpty || !ekMap.isEmpty {
            try await sendSyncBatch(upsertPayloads)
        }

        // Refresh DB state after upsert for push/delete steps
        let refreshedState = try await fetchSyncState()

        // Step 5: PUSH — create/update in EventKit for pending_push items
        for dbRow in refreshedState where dbRow.sync_status == "pending_push" {
            do {
                let confirmation = try await pushToEventKit(dbRow, existingEvents: ekMap)
                confirmations.append(confirmation)
            } catch {
                logger.error("[CalendarSync] Push failed for \(dbRow.event_id): \(error.localizedDescription)")
            }
        }

        // Step 6: DELETE — remove from EventKit for deleted_local items
        for dbRow in refreshedState where dbRow.sync_status == "deleted_local" {
            do {
                let confirmation = try await deleteFromEventKit(dbRow, existingEvents: ekMap)
                confirmations.append(confirmation)
            } catch {
                logger.error("[CalendarSync] Delete failed for \(dbRow.event_id): \(error.localizedDescription)")
            }
        }

        // Confirm all sync operations back to DB
        if !confirmations.isEmpty {
            try await confirmSyncOperations(confirmations)
        }

        lastSyncDate = Date()
        lastSyncEventCount = ekMap.count
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        logger.info("[CalendarSync] Sync complete: \(ekMap.count) EK, \(upsertPayloads.count) upserted, \(confirmations.count) confirmed")
    }

    // MARK: - Step 1: Fetch Events from EventKit

    func fetchEvents() -> [EKEvent] {
        let calendar = Constants.Dubai.calendar
        let now = Date()

        guard let startDate = calendar.date(byAdding: .day, value: -30, to: now),
              let endDate = calendar.date(byAdding: .day, value: 90, to: now) else {
            logger.error("[CalendarSync] Failed to calculate date range for calendar sync")
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
    }

    // MARK: - Step 2: Fetch DB Sync State

    private func fetchSyncState() async throws -> [DBCalendarEventState] {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-calendar-sync-state") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = KeychainManager.shared.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalendarSyncStateResponse.self, from: data)
        return decoded.events
    }

    // MARK: - Step 3: Send Diff-Aware Upsert Batch

    private func sendSyncBatch(_ events: [CalendarEventPayload]) async throws {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-calendar-sync") else {
            throw APIError.invalidURL
        }

        let payload = CalendarSyncPayload(
            client_id: UUID().uuidString,
            device: await UIDevice.current.name,
            source: "ios_eventkit",
            captured_at: isoFormatter.string(from: Date()),
            events: events
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = KeychainManager.shared.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Step 5: Push to EventKit

    private func pushToEventKit(_ dbRow: DBCalendarEventState, existingEvents: [String: EKEvent]) async throws -> CalendarSyncConfirmation {
        let isNewEvent = dbRow.event_id.hasPrefix("nexus-")

        var ekEvent: EKEvent

        if isNewEvent {
            ekEvent = EKEvent(eventStore: eventStore)
            ekEvent.calendar = defaultCalendar(named: dbRow.calendar_name)
        } else if let existing = existingEvents[dbRow.event_id] {
            ekEvent = existing
        } else {
            // Fallback: try to find by title+start tuple
            if let match = existingEvents.values.first(where: {
                $0.title == dbRow.title && $0.calendar?.title == dbRow.calendar_name && $0.startDate == dbRow.start_at_parsed
            }) {
                ekEvent = match
            } else {
                ekEvent = EKEvent(eventStore: eventStore)
                ekEvent.calendar = defaultCalendar(named: dbRow.calendar_name)
            }
        }

        ekEvent.title = dbRow.title ?? "Untitled"
        ekEvent.notes = dbRow.notes
        ekEvent.location = dbRow.location
        ekEvent.isAllDay = dbRow.is_all_day ?? false

        if let startAt = dbRow.start_at_parsed {
            ekEvent.startDate = startAt
        }
        if let endAt = dbRow.end_at_parsed {
            ekEvent.endDate = endAt
        }

        try eventStore.save(ekEvent, span: .thisEvent)

        let newModDate = ekEvent.lastModifiedDate ?? Date()

        return CalendarSyncConfirmation(
            db_id: dbRow.id,
            db_event_id: dbRow.event_id,
            eventkit_id: ekEvent.eventIdentifier,
            eventkit_modified_at: isoFormatter.string(from: newModDate),
            action: "synced"
        )
    }

    // MARK: - Step 6: Delete from EventKit

    private func deleteFromEventKit(_ dbRow: DBCalendarEventState, existingEvents: [String: EKEvent]) async throws -> CalendarSyncConfirmation {
        if let ekEvent = existingEvents[dbRow.event_id] {
            try eventStore.remove(ekEvent, span: .thisEvent)
        }

        return CalendarSyncConfirmation(
            db_id: dbRow.id,
            db_event_id: dbRow.event_id,
            eventkit_id: nil,
            eventkit_modified_at: nil,
            action: "deleted"
        )
    }

    // MARK: - Confirm Sync Operations

    private func confirmSyncOperations(_ confirmations: [CalendarSyncConfirmation]) async throws {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-calendar-confirm-sync") else {
            throw APIError.invalidURL
        }

        let body = ConfirmCalendarSyncPayload(confirmations: confirmations)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = KeychainManager.shared.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - CRUD Operations

    func createEvent(title: String, startAt: Date, endAt: Date, isAllDay: Bool = false, calendarName: String? = nil, location: String? = nil, notes: String? = nil) async throws -> EKEvent {
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = title
        ekEvent.startDate = startAt
        ekEvent.endDate = endAt
        ekEvent.isAllDay = isAllDay
        ekEvent.location = location
        ekEvent.notes = notes
        ekEvent.calendar = defaultCalendar(named: calendarName)

        try eventStore.save(ekEvent, span: .thisEvent)
        logger.info("[CalendarSync] Created event: \(title)")

        // Trigger sync to push to DB
        try await syncAllData()

        return ekEvent
    }

    func updateEvent(_ event: EKEvent, title: String? = nil, startAt: Date? = nil, endAt: Date? = nil, isAllDay: Bool? = nil, location: String? = nil, notes: String? = nil) async throws {
        if let title = title { event.title = title }
        if let startAt = startAt { event.startDate = startAt }
        if let endAt = endAt { event.endDate = endAt }
        if let isAllDay = isAllDay { event.isAllDay = isAllDay }
        if let location = location { event.location = location }
        if let notes = notes { event.notes = notes }

        try eventStore.save(event, span: .thisEvent)
        logger.info("[CalendarSync] Updated event: \(event.title ?? "Untitled")")

        // Trigger sync to push to DB
        try await syncAllData()
    }

    func deleteEvent(_ event: EKEvent) async throws {
        let title = event.title ?? "Untitled"
        try eventStore.remove(event, span: .thisEvent)
        logger.info("[CalendarSync] Deleted event: \(title)")

        // Trigger sync to update DB
        try await syncAllData()
    }

    func deleteEventById(_ eventId: String) async throws {
        // First try to find the event locally
        let ekEvents = fetchEvents()
        if let event = ekEvents.first(where: { $0.eventIdentifier == eventId }) {
            try await deleteEvent(event)
        } else {
            // Event not in EventKit, mark as deleted in DB
            guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-calendar-delete") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = KeychainManager.shared.apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            }
            request.httpBody = try JSONEncoder().encode(["event_id": eventId])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            logger.info("[CalendarSync] Deleted event from DB: \(eventId)")
        }
    }

    // MARK: - Helpers

    private func makePayload(from event: EKEvent) -> CalendarEventPayload {
        CalendarEventPayload(
            event_id: event.eventIdentifier,
            title: event.title,
            start_at: isoFormatter.string(from: event.startDate),
            end_at: isoFormatter.string(from: event.endDate),
            is_all_day: event.isAllDay,
            calendar_name: event.calendar?.title,
            location: event.location,
            notes: event.notes,
            recurrence_rule: event.hasRecurrenceRules ? event.recurrenceRules?.first?.description : nil,
            eventkit_modified_at: event.lastModifiedDate.map { isoFormatter.string(from: $0) }
        )
    }

    func defaultCalendar(named name: String?) -> EKCalendar {
        if let name = name,
           let cal = eventStore.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) {
            return cal
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents ?? eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            logger.error("[CalendarSync] No calendar available for writing")
            fatalError("No calendar available for writing - this should not happen on iOS")
        }
        return calendar
    }

    func availableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    private func parseISO8601(_ string: String) -> Date? {
        isoFormatter.date(from: string)
    }
}

// MARK: - Models

struct CalendarSyncPayload: Codable {
    let client_id: String
    let device: String
    let source: String
    let captured_at: String
    let events: [CalendarEventPayload]
}

struct CalendarEventPayload: Codable {
    let event_id: String
    let title: String?
    let start_at: String
    let end_at: String
    let is_all_day: Bool
    let calendar_name: String?
    let location: String?
    let notes: String?
    let recurrence_rule: String?
    let eventkit_modified_at: String?

    init(event_id: String, title: String?, start_at: String, end_at: String, is_all_day: Bool,
         calendar_name: String?, location: String?, notes: String?, recurrence_rule: String?,
         eventkit_modified_at: String? = nil) {
        self.event_id = event_id
        self.title = title
        self.start_at = start_at
        self.end_at = end_at
        self.is_all_day = is_all_day
        self.calendar_name = calendar_name
        self.location = location
        self.notes = notes
        self.recurrence_rule = recurrence_rule
        self.eventkit_modified_at = eventkit_modified_at
    }
}

struct CalendarSyncResponse: Codable {
    let success: Bool
    let inserted: InsertedCounts?
    let timestamp: String?
    let error: String?

    struct InsertedCounts: Codable {
        let events: Int
        let updated: Int?
        let total: Int?
    }
}

struct CalendarSyncStateResponse: Codable {
    let success: Bool
    let events: [DBCalendarEventState]
    let count: Int
}

struct DBCalendarEventState: Codable {
    let id: Int
    let event_id: String
    let title: String?
    let start_at: String
    let end_at: String
    let is_all_day: Bool?
    let calendar_name: String?
    let location: String?
    let notes: String?
    let recurrence_rule: String?
    let sync_status: String?
    let eventkit_modified_at: Date?
    let origin: String?
    let updated_at: Date?

    var start_at_parsed: Date? {
        ISO8601DateFormatter().date(from: start_at)
    }

    var end_at_parsed: Date? {
        ISO8601DateFormatter().date(from: end_at)
    }
}

struct CalendarSyncConfirmation: Codable {
    let db_id: Int
    let db_event_id: String
    let eventkit_id: String?
    let eventkit_modified_at: String?
    let action: String
}

struct ConfirmCalendarSyncPayload: Codable {
    let confirmations: [CalendarSyncConfirmation]
}

// Legacy model for backward compatibility
struct CalendarEvent: Codable {
    let event_id: String
    let title: String?
    let start_at: String
    let end_at: String
    let is_all_day: Bool
    let calendar_name: String?
    let location: String?
    let notes: String?
    let recurrence_rule: String?
}
