import Foundation

// MARK: - Data State Management

/// Unified state for any data-driven card or view
/// Supports 4 states: loading, empty, partial (syncing), fresh
enum DataState<T> {
    case loading
    case empty
    case partial(T, staleMinutes: Int)
    case fresh(T)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isPartial: Bool {
        if case .partial = self { return true }
        return false
    }

    var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }

    var data: T? {
        switch self {
        case .loading, .empty:
            return nil
        case .partial(let data, _), .fresh(let data):
            return data
        }
    }

    var staleMinutes: Int? {
        if case .partial(_, let minutes) = self {
            return minutes
        }
        return nil
    }
}

// MARK: - Freshness

enum Freshness {
    case fresh          // < 5 min old
    case recent         // 5-30 min old
    case stale          // 30-60 min old
    case old            // > 60 min old
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
