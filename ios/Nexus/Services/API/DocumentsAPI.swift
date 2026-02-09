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
        let base = "/webhook/nexus-reminders"
        var queryParams: [String: String] = [:]
        if let start = start { queryParams["start"] = start }
        if let end = end { queryParams["end"] = end }
        let endpoint = queryParams.isEmpty ? base : buildPath(base, query: queryParams)
        return try await get(endpoint)
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
        var queryParams: [String: String] = [:]
        if let query = query, !query.isEmpty {
            queryParams["q"] = query
        }
        if let tag = tag, !tag.isEmpty {
            queryParams["tag"] = tag
        }
        queryParams["limit"] = "\(limit)"

        let path = buildPath("/webhook/nexus-notes-search", query: queryParams)
        return try await get(path)
    }

    func updateNote(id: Int, title: String?, tags: [String]?) async throws -> NoteUpdateResponse {
        struct Body: Encodable {
            let title: String?
            let tags: [String]?
        }
        let path = buildPath("/webhook/nexus-note-update", query: ["id": "\(id)"])
        return try await put(path, body: Body(title: title, tags: tags))
    }

    func deleteNote(id: Int) async throws -> NoteDeleteResponse {
        let path = buildPath("/webhook/nexus-note-delete", query: ["id": "\(id)"])
        return try await delete(path)
    }
}
