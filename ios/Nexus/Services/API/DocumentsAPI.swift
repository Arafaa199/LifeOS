import Foundation

// MARK: - Documents API Client

/// Handles documents, reminders, and notes endpoints
class DocumentsAPI: BaseAPIClient {
    static let shared = DocumentsAPI()

    private init() {
        super.init(category: "documents-api")
    }

    // MARK: - Documents

    func fetchDocuments() async throws -> DocumentsResponse {
        return try await get("/webhook/nexus-documents")
    }

    // MARK: - Reminders

    func fetchReminders(start: String? = nil, end: String? = nil) async throws -> RemindersDisplayResponse {
        var params: [String] = []
        if let start = start { params.append("start=\(start)") }
        if let end = end { params.append("end=\(end)") }
        let queryString = params.isEmpty ? "" : "?\(params.joined(separator: "&"))"
        return try await get("/webhook/nexus-reminders\(queryString)")
    }

    func createReminder(_ request: ReminderCreateRequest) async throws -> ReminderCreateResponse {
        try await post("/webhook/nexus-reminder-create", body: request)
    }

    func updateReminder(_ request: ReminderUpdateRequest) async throws -> ReminderUpdateResponse {
        try await post("/webhook/nexus-reminder-update", body: request)
    }

    func deleteReminder(id: Int? = nil, reminderId: String? = nil) async throws -> ReminderDeleteResponse {
        let request = ReminderDeleteRequest(id: id, reminderId: reminderId)
        return try await post("/webhook/nexus-reminder-delete", body: request)
    }

    func toggleReminderCompletion(reminderId: String, isCompleted: Bool) async throws -> ReminderUpdateResponse {
        let completedDate = isCompleted ? ISO8601DateFormatter().string(from: Date()) : nil
        let request = ReminderUpdateRequest(
            id: nil,
            reminderId: reminderId,
            title: nil,
            notes: nil,
            dueDate: nil,
            isCompleted: isCompleted,
            completedDate: completedDate,
            priority: nil,
            listName: nil
        )
        return try await updateReminder(request)
    }

    // MARK: - Notes

    func searchNotes(query: String? = nil, tag: String? = nil, limit: Int = 50) async throws -> NotesSearchResponse {
        var params: [String] = []
        if let query = query, !query.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            params.append("q=\(encoded)")
        }
        if let tag = tag, !tag.isEmpty {
            let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
            params.append("tag=\(encoded)")
        }
        params.append("limit=\(limit)")

        let queryString = params.joined(separator: "&")
        return try await get("/webhook/nexus-notes-search?\(queryString)")
    }
}
