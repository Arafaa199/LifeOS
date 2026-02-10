import Foundation

// MARK: - Note

struct Note: Codable, Identifiable {
    let noteId: Int?
    let relativePath: String
    let title: String?
    let tags: [String]?
    let wordCount: Int?
    let fileModifiedAt: String?
    let indexedAt: String?

    var id: String { relativePath }

    enum CodingKeys: String, CodingKey {
        case noteId = "id"
        case relativePath = "relative_path"
        case title
        case tags
        case wordCount = "word_count"
        case fileModifiedAt = "file_modified_at"
        case indexedAt = "indexed_at"
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Extract filename without extension from path
        let filename = (relativePath as NSString).lastPathComponent
        return (filename as NSString).deletingPathExtension
    }

    var folder: String? {
        let components = relativePath.split(separator: "/")
        guard let first = components.first else { return nil }
        return String(first)
    }

    var relativeDate: String? {
        guard let dateStr = fileModifiedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateStr) else { return nil }
            return formatRelativeDate(date)
        }
        return formatRelativeDate(date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h ago"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return dateFormatter.string(from: date)
        }
    }
}

// MARK: - API Responses

struct NotesSearchResponse: Codable {
    let success: Bool
    let notes: [Note]
    let count: Int
}

struct NoteUpdateResponse: Codable {
    let success: Bool
    let message: String?
}

struct NoteDeleteResponse: Codable {
    let success: Bool
    let message: String?
}
