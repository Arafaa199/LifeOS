import Foundation
import os

// MARK: - Sync Conflict Model

/// Represents a sync conflict detected by the server
struct SyncConflict: Codable {
    let conflictType: String      // "duplicate", "version_mismatch", "stale_update"
    let serverVersion: String?    // Server's current value
    let clientVersion: String?    // What client tried to send
    let resolution: String        // "server_wins", "client_wins", "merged"
    let message: String           // Human-readable description

    enum CodingKeys: String, CodingKey {
        case conflictType = "conflict_type"
        case serverVersion = "server_version"
        case clientVersion = "client_version"
        case resolution, message
    }
}

// MARK: - Conflict Resolver Actor

/// Handles sync conflicts between offline queue and server state
actor ConflictResolver {
    static let shared = ConflictResolver()
    private let logger = Logger(subsystem: "com.nexus.app", category: "ConflictResolver")

    /// Recent conflicts for UI display
    private(set) var recentConflicts: [ResolvedConflict] = []

    struct ResolvedConflict: Identifiable {
        let id = UUID()
        let timestamp: Date
        let description: String
        let resolution: String
        let wasAutoResolved: Bool
    }

    /// Check if an API response indicates a conflict (HTTP 409)
    /// Returns true if a conflict was detected and processed
    func handleConflictResponse(_ data: Data, for request: String) -> Bool {
        do {
            let conflict = try JSONDecoder().decode(SyncConflict.self, from: data)

            let resolved = ResolvedConflict(
                timestamp: Date(),
                description: "\(request): \(conflict.message)",
                resolution: conflict.resolution,
                wasAutoResolved: conflict.resolution != "needs_review"
            )

            recentConflicts.append(resolved)

            // Keep only last 50 conflicts
            if recentConflicts.count > 50 {
                recentConflicts.removeFirst(recentConflicts.count - 50)
            }

            logger.info("Sync conflict resolved: \(conflict.message) → \(conflict.resolution)")

            // Post notification for UI
            NotificationCenter.default.post(
                name: .syncConflictResolved,
                object: nil,
                userInfo: [
                    "conflict": resolved.description,
                    "resolution": resolved.resolution,
                    "wasAutoResolved": resolved.wasAutoResolved
                ]
            )

            return true
        } catch {
            logger.error("Failed to decode 409 conflict response for \(request): \(error.localizedDescription)")
            return false
        }
    }

    /// Get all recent conflicts (thread-safe)
    func getRecentConflicts() -> [ResolvedConflict] {
        return recentConflicts
    }

    /// Clear old conflicts
    func clearConflicts() {
        recentConflicts.removeAll()
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let syncConflictResolved = Notification.Name("syncConflictResolved")
}
