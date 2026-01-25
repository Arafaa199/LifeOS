import Foundation
import EventKit
import UIKit
import Combine

@MainActor
class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()

    @Published var lastSyncDate: Date?
    @Published var lastSyncEventCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "calendar_last_sync_date"

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
            print("[CalendarSync] Access request failed: \(error)")
            return false
        }
    }

    func syncAllData() async throws {
        guard !isSyncing else { return }

        updateAuthorizationStatus()
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else {
            print("[CalendarSync] Not authorized to access calendar")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let events = fetchEvents()
        guard !events.isEmpty else {
            print("[CalendarSync] No events to sync")
            return
        }

        let response = try await sendToWebhook(events)

        if response.success {
            lastSyncDate = Date()
            lastSyncEventCount = events.count
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            print("[CalendarSync] Synced \(events.count) events")
        }
    }

    private func fetchEvents() -> [CalendarEvent] {
        let calendar = Calendar.current

        let startDate = calendar.date(byAdding: .day, value: -30, to: Date())!
        let endDate = calendar.date(byAdding: .day, value: 7, to: Date())!

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                event_id: event.eventIdentifier,
                title: event.title,
                start_at: ISO8601DateFormatter().string(from: event.startDate),
                end_at: ISO8601DateFormatter().string(from: event.endDate),
                is_all_day: event.isAllDay,
                calendar_name: event.calendar.title,
                location: event.location,
                notes: event.notes,
                recurrence_rule: event.hasRecurrenceRules ? event.recurrenceRules?.first?.description : nil
            )
        }
    }

    private func sendToWebhook(_ events: [CalendarEvent]) async throws -> CalendarSyncResponse {
        let baseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
        guard let url = URL(string: "\(baseURL)/webhook/nexus-calendar-sync") else {
            throw APIError.invalidURL
        }

        let payload = CalendarSyncPayload(
            client_id: UUID().uuidString,
            device: await UIDevice.current.name,
            source: "ios_eventkit",
            captured_at: ISO8601DateFormatter().string(from: Date()),
            events: events
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = UserDefaults.standard.string(forKey: "nexusAPIKey") {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(CalendarSyncResponse.self, from: data)
    }
}

struct CalendarSyncPayload: Codable {
    let client_id: String
    let device: String
    let source: String
    let captured_at: String
    let events: [CalendarEvent]
}

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
