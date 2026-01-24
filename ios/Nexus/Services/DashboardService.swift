import Foundation

class DashboardService {
    static let shared = DashboardService()

    private let api = NexusAPI.shared
    private let cache = CacheManager.shared
    private let cacheKey = "dashboard_payload"

    private init() {}

    // MARK: - Fetch Dashboard

    /// Fetches the unified dashboard payload from the server.
    /// Returns cached data if offline or on failure.
    func fetchDashboard() async throws -> DashboardResult {
        // Try network fetch
        do {
            let response: DashboardResponse = try await api.get("/webhook/nexus-dashboard-today")

            if let payload = response.data {
                cache.save(payload, forKey: cacheKey)
                return DashboardResult(payload: payload, source: .network, lastUpdated: Date())
            } else if let error = response.error {
                throw DashboardError.serverError(error)
            } else {
                throw DashboardError.emptyResponse
            }
        } catch {
            // Network failed, try cache
            if let cached = loadCached() {
                return cached
            }
            throw error
        }
    }

    /// Returns cached dashboard data if available.
    func loadCached() -> DashboardResult? {
        guard let payload = cache.load(DashboardPayload.self, forKey: cacheKey),
              let timestamp = UserDefaults.standard.object(forKey: "\(cacheKey)_timestamp") as? Date else {
            return nil
        }
        return DashboardResult(payload: payload, source: .cache, lastUpdated: timestamp)
    }

    /// Returns the age of the cached data in seconds, or nil if no cache.
    func cacheAge() -> TimeInterval? {
        return cache.getCacheAge(forKey: cacheKey)
    }

    /// Clears the dashboard cache.
    func clearCache() {
        cache.delete(forKey: cacheKey)
    }
}

// MARK: - Dashboard Result

struct DashboardResult {
    let payload: DashboardPayload
    let source: DataSource
    let lastUpdated: Date

    enum DataSource {
        case network
        case cache
    }

    var isStale: Bool {
        // Consider data stale if older than 5 minutes
        return Date().timeIntervalSince(lastUpdated) > 300
    }

    var lastUpdatedFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
}

// MARK: - Dashboard Error

enum DashboardError: LocalizedError {
    case serverError(String)
    case emptyResponse
    case noCache

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .emptyResponse:
            return "Server returned empty response"
        case .noCache:
            return "No cached data available"
        }
    }
}
