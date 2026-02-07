import Foundation
import EventKit
import UIKit
import Combine
import os

@MainActor
class ReminderSyncService: ObservableObject {
    static let shared = ReminderSyncService()

    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.nexus", category: "ReminderSync")

    @Published var lastSyncDate: Date?
    @Published var lastSyncReminderCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "reminders_last_sync_date"
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = Constants.Dubai.timeZone
        return f
    }()

    private let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = Constants.Dubai.timeZone
        return f
    }()

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
            logger.error("[ReminderSync] Access request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Main Sync Entry Point (6-step bidirectional diff)

    func syncAllData() async throws {
        guard !isSyncing else { return }

        updateAuthorizationStatus()
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else {
            logger.warning("[ReminderSync] Not authorized to access reminders")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Step 1: PULL from EventKit
        let ekReminders = try await fetchAllReminders()
        let ekMap = Dictionary(ekReminders.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        // Step 2: PULL from DB
        let dbState = try await fetchSyncState()
        let dbMap = Dictionary(dbState.map { ($0.reminder_id, $0) }, uniquingKeysWith: { first, _ in first })

        var upsertPayloads: [ReminderPayload] = []
        var confirmations: [SyncConfirmation] = []

        // Step 3: DIFF — compare EK reminders against DB
        for (ekId, ekReminder) in ekMap {
            let payload = makePayload(from: ekReminder)

            if let dbRow = dbMap[ekId] {
                if dbRow.sync_status == "pending_push" {
                    // Conflict: DB has pending changes. Last-writer-wins by timestamp.
                    if let ekMod = ekReminder.lastModifiedDate,
                       let dbMod = dbRow.updated_at,
                       ekMod > dbMod {
                        upsertPayloads.append(payload)
                    }
                    // else: DB wins, will push in step 5
                } else if dbRow.sync_status == "synced" {
                    if let ekMod = ekReminder.lastModifiedDate,
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
                // New remote reminder, not in DB
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
                let confirmation = try await pushToEventKit(dbRow, existingReminders: ekMap)
                confirmations.append(confirmation)
            } catch {
                logger.error("[ReminderSync] Push failed for \(dbRow.reminder_id): \(error.localizedDescription)")
            }
        }

        // Step 6: DELETE — remove from EventKit for deleted_local items
        for dbRow in refreshedState where dbRow.sync_status == "deleted_local" {
            do {
                let confirmation = try await deleteFromEventKit(dbRow, existingReminders: ekMap)
                confirmations.append(confirmation)
            } catch {
                logger.error("[ReminderSync] Delete failed for \(dbRow.reminder_id): \(error.localizedDescription)")
            }
        }

        // Confirm all sync operations back to DB
        if !confirmations.isEmpty {
            try await confirmSyncOperations(confirmations)
        }

        lastSyncDate = Date()
        lastSyncReminderCount = ekMap.count
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        logger.info("[ReminderSync] Sync complete: \(ekMap.count) EK, \(upsertPayloads.count) upserted, \(confirmations.count) confirmed")
    }

    // MARK: - Step 1: Fetch All Reminders from EventKit

    private func fetchAllReminders() async throws -> [EKReminder] {
        let calendar = Constants.Dubai.calendar

        // Expanded window: ALL incomplete + completed in last 14 days
        let incompletePredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        let completedPredicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: calendar.date(byAdding: .day, value: -14, to: Date())!,
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

        return all
    }

    // MARK: - Step 2: Fetch DB Sync State

    private func fetchSyncState() async throws -> [DBReminderState] {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-reminders-sync-state") else {
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

        let decoded = try JSONDecoder().decode(SyncStateResponse.self, from: data)
        return decoded.reminders
    }

    // MARK: - Step 3: Send Diff-Aware Upsert Batch

    private func sendSyncBatch(_ reminders: [ReminderPayload]) async throws {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-reminders-sync") else {
            throw APIError.invalidURL
        }

        let payload = ReminderSyncPayload(
            client_id: UUID().uuidString,
            device: await UIDevice.current.name,
            source: "ios_eventkit",
            captured_at: isoFormatter.string(from: Date()),
            reminders: reminders
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

    private func pushToEventKit(_ dbRow: DBReminderState, existingReminders: [String: EKReminder]) async throws -> SyncConfirmation {
        let isNewReminder = dbRow.reminder_id.hasPrefix("nexus-")

        var ekReminder: EKReminder

        if isNewReminder {
            ekReminder = EKReminder(eventStore: eventStore)
            ekReminder.calendar = try defaultReminderCalendar(named: dbRow.list_name)
        } else if let existing = existingReminders[dbRow.reminder_id] {
            ekReminder = existing
        } else {
            // Fallback: try to find by title+list tuple
            if let match = existingReminders.values.first(where: {
                $0.title == dbRow.title && $0.calendar?.title == dbRow.list_name && $0.dueDateComponents?.date == dbRow.due_date_parsed
            }) {
                ekReminder = match
            } else {
                ekReminder = EKReminder(eventStore: eventStore)
                ekReminder.calendar = try defaultReminderCalendar(named: dbRow.list_name)
            }
        }

        ekReminder.title = dbRow.title
        ekReminder.notes = dbRow.notes
        ekReminder.priority = dbRow.priority ?? 0
        ekReminder.isCompleted = dbRow.is_completed ?? false

        if let dueDateStr = dbRow.due_date, let dueDate = parseISO8601(dueDateStr) {
            ekReminder.dueDateComponents = Constants.Dubai.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            ekReminder.dueDateComponents = nil
        }

        if let completedStr = dbRow.completed_date, let completedDate = parseISO8601(completedStr) {
            ekReminder.completionDate = completedDate
        }

        try eventStore.save(ekReminder, commit: true)

        let newModDate = ekReminder.lastModifiedDate ?? Date()

        return SyncConfirmation(
            db_id: dbRow.id,
            db_reminder_id: dbRow.reminder_id,
            eventkit_id: ekReminder.calendarItemIdentifier,
            eventkit_modified_at: isoFormatter.string(from: newModDate),
            action: "synced"
        )
    }

    // MARK: - Step 6: Delete from EventKit

    private func deleteFromEventKit(_ dbRow: DBReminderState, existingReminders: [String: EKReminder]) async throws -> SyncConfirmation {
        if let ekReminder = existingReminders[dbRow.reminder_id] {
            try eventStore.remove(ekReminder, commit: true)
        }

        return SyncConfirmation(
            db_id: dbRow.id,
            db_reminder_id: dbRow.reminder_id,
            eventkit_id: nil,
            eventkit_modified_at: nil,
            action: "deleted"
        )
    }

    // MARK: - Confirm Sync Operations

    private func confirmSyncOperations(_ confirmations: [SyncConfirmation]) async throws {
        guard let url = NetworkConfig.shared.url(for: "/webhook/nexus-reminder-confirm-sync") else {
            throw APIError.invalidURL
        }

        let body = ConfirmSyncPayload(confirmations: confirmations)

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

    // MARK: - Helpers

    private func makePayload(from reminder: EKReminder) -> ReminderPayload {
        ReminderPayload(
            reminder_id: reminder.calendarItemIdentifier,
            title: reminder.title,
            notes: reminder.notes,
            due_date: reminder.dueDateComponents?.date.map { isoFormatter.string(from: $0) },
            is_completed: reminder.isCompleted,
            completed_date: reminder.completionDate.map { isoFormatter.string(from: $0) },
            priority: reminder.priority,
            list_name: reminder.calendar?.title,
            eventkit_modified_at: reminder.lastModifiedDate.map { isoFormatter.string(from: $0) }
        )
    }

    private func defaultReminderCalendar(named name: String?) throws -> EKCalendar {
        if let name = name,
           let cal = eventStore.calendars(for: .reminder).first(where: { $0.title == name }) {
            return cal
        }
        if let name = name {
            let newCal = EKCalendar(for: .reminder, eventStore: eventStore)
            newCal.title = name
            newCal.source = eventStore.defaultCalendarForNewReminders()?.source
                ?? eventStore.sources.first(where: { $0.sourceType == .local })
            if let _ = try? eventStore.saveCalendar(newCal, commit: true) {
                logger.info("[ReminderSync] Created calendar: \(name)")
                return newCal
            }
        }
        guard let calendar = eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first else {
            logger.error("[ReminderSync] No reminder calendar available")
            throw APIError.custom("No reminder calendar available. Check Reminders permissions in Settings.")
        }
        return calendar
    }

    private func parseISO8601(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }
}

// MARK: - Models

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
    let eventkit_modified_at: String?

    init(reminder_id: String, title: String?, notes: String?, due_date: String?,
         is_completed: Bool, completed_date: String?, priority: Int, list_name: String?,
         eventkit_modified_at: String? = nil) {
        self.reminder_id = reminder_id
        self.title = title
        self.notes = notes
        self.due_date = due_date
        self.is_completed = is_completed
        self.completed_date = completed_date
        self.priority = priority
        self.list_name = list_name
        self.eventkit_modified_at = eventkit_modified_at
    }
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

struct SyncStateResponse: Codable {
    let success: Bool
    let reminders: [DBReminderState]
    let count: Int
}

struct DBReminderState: Codable {
    let id: Int
    let reminder_id: String
    let title: String?
    let notes: String?
    let due_date: String?
    let is_completed: Bool?
    let completed_date: String?
    let priority: Int?
    let list_name: String?
    let sync_status: String?
    let eventkit_modified_at: Date?
    let origin: String?
    let updated_at: Date?

    var due_date_parsed: Date? {
        guard let d = due_date else { return nil }
        return ISO8601DateFormatter().date(from: d)
    }
}

struct SyncConfirmation: Codable {
    let db_id: Int
    let db_reminder_id: String
    let eventkit_id: String?
    let eventkit_modified_at: String?
    let action: String
}

struct ConfirmSyncPayload: Codable {
    let confirmations: [SyncConfirmation]
}
