import Foundation
import EventKit
import UIKit
import Combine

@MainActor
class ReminderSyncService: ObservableObject {
    static let shared = ReminderSyncService()

    private let eventStore = EKEventStore()

    @Published var lastSyncDate: Date?
    @Published var lastSyncReminderCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "reminders_last_sync_date"

    private init() {
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToReminders()
                updateAuthorizationStatus()
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .reminder)
                updateAuthorizationStatus()
                return granted
            }
        } catch {
            print("[ReminderSync] Access request failed: \(error)")
            return false
        }
    }

    func syncAllData() async throws {
        guard !isSyncing else { return }

        updateAuthorizationStatus()
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else {
            print("[ReminderSync] Not authorized to access reminders")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let reminders = try await fetchReminders()
        guard !reminders.isEmpty else {
            print("[ReminderSync] No reminders to sync")
            return
        }

        let response = try await sendToWebhook(reminders)

        if response.success {
            lastSyncDate = Date()
            lastSyncReminderCount = reminders.count
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            print("[ReminderSync] Synced \(reminders.count) reminders")
        }
    }

    private func fetchReminders() async throws -> [ReminderPayload] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -30, to: Date())!
        let endDate = calendar.date(byAdding: .day, value: 7, to: Date())!
        let isoFormatter = ISO8601DateFormatter()

        let incompletePredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startDate,
            ending: endDate,
            calendars: nil
        )

        let completedPredicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: calendar.date(byAdding: .day, value: -7, to: Date())!,
            ending: Date(),
            calendars: nil
        )

        async let incompleteResults = withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: incompletePredicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        async let completedResults = withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: completedPredicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        let incomplete = try await incompleteResults
        let completed = try await completedResults

        var seen = Set<String>()
        var all: [EKReminder] = []
        for r in incomplete + completed {
            if seen.insert(r.calendarItemIdentifier).inserted {
                all.append(r)
            }
        }

        return all.map { reminder in
            ReminderPayload(
                reminder_id: reminder.calendarItemIdentifier,
                title: reminder.title,
                notes: reminder.notes,
                due_date: reminder.dueDateComponents?.date.map { isoFormatter.string(from: $0) },
                is_completed: reminder.isCompleted,
                completed_date: reminder.completionDate.map { isoFormatter.string(from: $0) },
                priority: reminder.priority,
                list_name: reminder.calendar?.title
            )
        }
    }

    private func sendToWebhook(_ reminders: [ReminderPayload]) async throws -> ReminderSyncResponse {
        let baseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
        guard let url = URL(string: "\(baseURL)/webhook/nexus-reminders-sync") else {
            throw APIError.invalidURL
        }

        let payload = ReminderSyncPayload(
            client_id: UUID().uuidString,
            device: await UIDevice.current.name,
            source: "ios_eventkit",
            captured_at: ISO8601DateFormatter().string(from: Date()),
            reminders: reminders
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = UserDefaults.standard.string(forKey: "nexusAPIKey") {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(ReminderSyncResponse.self, from: data)
    }
}

struct ReminderSyncPayload: Codable {
    let client_id: String
    let device: String
    let source: String
    let captured_at: String
    let reminders: [ReminderPayload]
}

struct ReminderPayload: Codable {
    let reminder_id: String
    let title: String?
    let notes: String?
    let due_date: String?
    let is_completed: Bool
    let completed_date: String?
    let priority: Int
    let list_name: String?
}

struct ReminderSyncResponse: Codable {
    let success: Bool
    let inserted: InsertedCounts?
    let timestamp: String?
    let error: String?

    struct InsertedCounts: Codable {
        let reminders: Int
        let updated: Int?
        let total: Int?
    }
}
