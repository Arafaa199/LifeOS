import Foundation

// MARK: - Reminder Create/Update Request

struct ReminderCreateRequest: Codable {
    let title: String
    let notes: String?
    let dueDate: String?
    let priority: Int
    let listName: String?

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case dueDate = "due_date"
        case priority
        case listName = "list_name"
    }
}

struct ReminderUpdateRequest: Codable {
    let id: Int?
    let reminderId: String?
    let title: String?
    let notes: String?
    let dueDate: String?
    let isCompleted: Bool?
    let completedDate: String?
    let priority: Int?
    let listName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reminderId = "reminder_id"
        case title
        case notes
        case dueDate = "due_date"
        case isCompleted = "is_completed"
        case completedDate = "completed_date"
        case priority
        case listName = "list_name"
    }
}

struct ReminderDeleteRequest: Codable {
    let id: Int?
    let reminderId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reminderId = "reminder_id"
    }
}

// MARK: - API Responses

struct ReminderCreateResponse: Codable {
    let success: Bool
    let reminder: CreatedReminder?
    let timestamp: String?

    struct CreatedReminder: Codable {
        let id: Int?
        let reminderId: String?
        let title: String?
        let syncStatus: String?

        enum CodingKeys: String, CodingKey {
            case id
            case reminderId = "reminder_id"
            case title
            case syncStatus = "sync_status"
        }
    }
}

struct ReminderUpdateResponse: Codable {
    let success: Bool
    let updated: UpdatedReminder?
    let timestamp: String?

    struct UpdatedReminder: Codable {
        let id: Int?
        let reminderId: String?
        let syncStatus: String?

        enum CodingKeys: String, CodingKey {
            case id
            case reminderId = "reminder_id"
            case syncStatus = "sync_status"
        }
    }
}

struct ReminderDeleteResponse: Codable {
    let success: Bool
    let deleted: DeletedReminder?
    let timestamp: String?

    struct DeletedReminder: Codable {
        let id: Int?
        let reminderId: String?
        let syncStatus: String?

        enum CodingKeys: String, CodingKey {
            case id
            case reminderId = "reminder_id"
            case syncStatus = "sync_status"
        }
    }
}
