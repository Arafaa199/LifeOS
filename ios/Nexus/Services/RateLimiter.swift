import Foundation
import os

/// Simple token-bucket rate limiter for API calls
actor RateLimiter {
    static let shared = RateLimiter()
    private let logger = Logger(subsystem: "com.nexus", category: "RateLimiter")

    /// Per-endpoint tracking
    private var lastCallTimes: [String: [Date]] = [:]

    /// Configuration per endpoint category
    struct Config {
        let maxCalls: Int       // Max calls in window
        let windowSeconds: Double  // Window duration
    }

    /// Default configs by endpoint type
    private let configs: [String: Config] = [
        "POST": Config(maxCalls: 10, windowSeconds: 60),    // 10 POSTs per minute
        "GET": Config(maxCalls: 30, windowSeconds: 60),      // 30 GETs per minute
        "DELETE": Config(maxCalls: 5, windowSeconds: 60),    // 5 DELETEs per minute
        "PUT": Config(maxCalls: 10, windowSeconds: 60),      // 10 PUTs per minute
    ]

    /// Track call count for cleanup frequency
    private var callCount: Int = 0
    private let cleanupFrequency = 50  // Cleanup every 50 requests

    /// Check if a request should be allowed
    func shouldAllow(endpoint: String, method: String = "POST") -> Bool {
        let config = configs[method] ?? Config(maxCalls: 20, windowSeconds: 60)
        let now = Date()
        let windowStart = now.addingTimeInterval(-config.windowSeconds)

        // Clean old entries
        var calls = (lastCallTimes[endpoint] ?? []).filter { $0 > windowStart }

        if calls.count >= config.maxCalls {
            logger.warning("Rate limited: \(endpoint) (\(calls.count)/\(config.maxCalls) in \(config.windowSeconds)s)")
            return false
        }

        calls.append(now)
        lastCallTimes[endpoint] = calls

        // Periodic cleanup of stale entries
        callCount += 1
        if callCount % cleanupFrequency == 0 {
            cleanupStaleEntries()
        }

        return true
    }

    /// Remove endpoint entries where all timestamps are outside the rate window
    private func cleanupStaleEntries() {
        let now = Date()
        var keysToRemove: [String] = []

        for (key, timestamps) in lastCallTimes {
            // Find the maximum window size needed for this endpoint
            let maxWindow = configs.values.map(\.windowSeconds).max() ?? 60.0
            let cutoff = now.addingTimeInterval(-maxWindow)

            let recentTimestamps = timestamps.filter { $0 > cutoff }
            if recentTimestamps.isEmpty {
                keysToRemove.append(key)
            }
        }

        for key in keysToRemove {
            lastCallTimes.removeValue(forKey: key)
        }

        if !keysToRemove.isEmpty {
            logger.debug("Cleaned up \(keysToRemove.count) stale rate limiter entries")
        }
    }

    /// Reset rate limiter (for testing)
    func reset() {
        lastCallTimes.removeAll()
    }
}
