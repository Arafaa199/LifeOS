import Foundation
import SwiftUI

// MARK: - Sync Phase

enum SyncPhase: Equatable {
    case idle
    case syncing(attemptStarted: Date)
    case succeeded(at: Date)
    case failed(at: Date, error: String)
}

// MARK: - Staleness

enum Staleness: Equatable {
    case fresh
    case stale
    case critical
    case neverSynced
    case error(String)

    var color: Color {
        switch self {
        case .fresh: return .green
        case .stale: return .orange
        case .critical, .error: return .red
        case .neverSynced: return .gray
        }
    }

    var icon: String {
        switch self {
        case .fresh: return "checkmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .critical: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .neverSynced: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .fresh: return "Fresh"
        case .stale: return "Stale"
        case .critical: return "Critical"
        case .neverSynced: return "Not synced"
        case .error(let msg): return msg
        }
    }
}

// MARK: - Domain State

struct DomainState: Equatable {
    var phase: SyncPhase = .idle
    var source: String?
    var detail: String?
    var itemCount: Int?

    var staleness: Staleness {
        switch phase {
        case .idle:
            return .neverSynced
        case .syncing:
            if let prev = lastSuccessDate {
                return Self.stalenessFromAge(Date().timeIntervalSince(prev))
            }
            return .neverSynced
        case .succeeded(let date):
            return Self.stalenessFromAge(Date().timeIntervalSince(date))
        case .failed(_, let error):
            return .error(error)
        }
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }

    var lastSuccessDate: Date? {
        if case .succeeded(let date) = phase { return date }
        return nil
    }

    var lastError: String? {
        if case .failed(_, let error) = phase { return error }
        return nil
    }

    var statusText: String {
        if isSyncing { return "Syncing..." }
        if let error = lastError { return error }
        guard let lastSync = lastSuccessDate else { return "Not synced" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    mutating func markSyncing() {
        phase = .syncing(attemptStarted: Date())
    }

    mutating func markSucceeded(source: String? = nil, detail: String? = nil, itemCount: Int? = nil) {
        phase = .succeeded(at: Date())
        self.source = source
        self.detail = detail
        self.itemCount = itemCount
    }

    mutating func markFailed(_ error: String) {
        phase = .failed(at: Date(), error: error)
    }

    private static func stalenessFromAge(_ age: TimeInterval) -> Staleness {
        if age < 300 { return .fresh }
        if age < 3600 { return .stale }
        return .critical
    }
}

// MARK: - Freshness (Presentation Helper for CardContainer/FreshnessBadge)

enum Freshness {
    case fresh
    case recent
    case stale
    case old
    case unknown

    init(from date: Date?) {
        guard let date = date else {
            self = .unknown
            return
        }

        let minutes = Int(-date.timeIntervalSinceNow / 60)

        switch minutes {
        case ..<5:
            self = .fresh
        case 5..<30:
            self = .recent
        case 30..<60:
            self = .stale
        default:
            self = .old
        }
    }

    var dotColor: String {
        switch self {
        case .fresh: return "green"
        case .recent: return "green"
        case .stale: return "orange"
        case .old: return "red"
        case .unknown: return "gray"
        }
    }

    var label: String {
        switch self {
        case .fresh: return "Live"
        case .recent: return "Recent"
        case .stale: return "Stale"
        case .old: return "Old"
        case .unknown: return "Unknown"
        }
    }
}
