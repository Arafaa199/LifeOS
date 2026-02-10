import Foundation

/// Documentation and usage examples for the ConflictResolver system
///
/// SYNC CONFLICT RESOLUTION STRATEGY: Last-Write-Wins with Auto-Resolution
///
/// ## Problem
/// When a user makes changes offline and syncs, the server may have received conflicting
/// updates. For example:
/// - SMS auto-import creates a transaction for the same merchant/date
/// - User manually adds the same transaction while offline
/// - Both attempt to sync → conflict detected
///
/// ## Solution: HTTP 409 Conflict + ConflictResolver
///
/// The server responds with HTTP 409 Conflict that includes:
/// - conflictType: "duplicate", "version_mismatch", "stale_update"
/// - serverVersion: The current server value
/// - clientVersion: What the client tried to send
/// - resolution: "server_wins", "client_wins", "merged"
/// - message: Human-readable description
///
/// ## Flow
///
/// 1. OfflineQueue.processQueue() sends a request → receives 409
/// 2. BaseAPIClient catches 409 → ConflictResolver.handleConflictResponse()
/// 3. ConflictResolver:
///    - Parses conflict details
///    - Logs the resolution
///    - Posts `.syncConflictResolved` notification
/// 4. ErrorClassification.classify(409) returns .clientError
/// 5. OfflineQueue removes item from queue (resolved, not failed)
/// 6. ConflictBannerView displays auto-dismiss notification to user
///
/// ## Key Points
///
/// - 409 = Conflict (not an error) — server auto-resolved it
/// - Item is removed from queue (not marked as failed)
/// - User is notified via subtle banner (auto-dismisses after 5s)
/// - Last-write-wins: Server's version takes precedence
/// - Safe: No data loss — server has the authoritative state
///
/// ## Example: SMS Auto-Import Conflict
///
/// Timeline:
/// 1. User goes offline, manually adds: "Coffee at Starbucks, AED 25"
/// 2. User reconnects, offline queue tries to sync
/// 3. Server already received SMS import: "Starbucks, AED 25" from same merchant/date
/// 4. Server detects duplicate, responds with 409:
///    {
///      "conflict_type": "duplicate",
///      "message": "Transaction already exists from SMS import (ID: 12345)",
///      "server_version": "SMS imported transaction",
///      "resolution": "server_wins"
///    }
/// 5. ConflictResolver processes 409 → posts notification
/// 6. Banner shown: "Sync Conflict Resolved: Transaction already exists from SMS import"
/// 7. User's queued item removed (no duplicate created)
///
/// ## Testing Conflict Resolution
///
/// To manually test:
/// ```swift
/// // In debug menu, trigger a simulated conflict:
/// Task {
///     // Create mock conflict response
///     let json = """
///     {
///       "conflict_type": "duplicate",
///       "message": "Transaction for Starbucks on 2024-02-08 already exists",
///       "resolution": "server_wins",
///       "server_version": "SMS imported"
///     }
///     """
///
///     let data = json.data(using: .utf8)!
///     let resolved = await ConflictResolver.shared.handleConflictResponse(
///         data,
///         for: "Transaction: Starbucks 25.0"
///     )
///     print("Conflict resolved: \(resolved)")
/// }
/// ```
///
/// ## Error Handling Decision Tree
///
/// Error received → ErrorClassification.classify(_:)
///   ├─ URLError (network) → .transient (retry)
///   ├─ APIError.serverError(409) → .clientError (DON'T RETRY — server resolved)
///   ├─ APIError.serverError(4xx) → .clientError (don't retry, discard)
///   ├─ APIError.serverError(5xx) → .transient (retry)
///   ├─ APIError (401/403) → .authError (don't retry)
///   └─ Other → .permanent (don't retry)
///
/// When .clientError is classified:
///   ├─ If 409 → ConflictResolver handles → remove from queue
///   └─ Else → Move to failed items
///
/// ## Integration Points
///
/// 1. BaseAPIClient.performRequest(_:)
///    - Detects 409 status code
///    - Calls ConflictResolver.handleConflictResponse()
///    - Throws APIError.serverError(409)
///
/// 2. OfflineQueue.processQueue()
///    - Catches error from sendRequest()
///    - Classifies via ErrorClassification.classify()
///    - Special handling for 409 in .clientError case
///    - Removes from queue instead of marking failed
///
/// 3. ContentView
///    - Displays ConflictBannerView for notifications
///    - Banner auto-dismisses after 5 seconds
///
/// ## UI/UX Design
///
/// Banner appearance:
/// - Icon: arrow.triangle.2.circlepath (sync resolve icon)
/// - Title: "Sync Conflict Resolved"
/// - Message: Conflict description from server
/// - Duration: Auto-dismiss after 5 seconds
/// - Style: Ultra-thin material background with rounded corners
/// - Dismissal: Manual close button available
///
/// This subtle approach keeps the user informed without being disruptive.
/// Conflicts are handled automatically without requiring user intervention.
///

// No runtime code in this file — purely documentation
