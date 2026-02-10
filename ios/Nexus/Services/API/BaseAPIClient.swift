import Foundation
import os

// MARK: - Circuit Breaker

/// Thread-safe circuit breaker shared across all API clients.
/// Prevents cascading failures by failing fast when the backend is down.
final class CircuitBreaker: @unchecked Sendable {
    enum State: String { case closed, open, halfOpen }

    static let shared = CircuitBreaker()

    private let lock = NSLock()
    private var _state: State = .closed
    private var _failureCount = 0
    private var _lastFailureTime: Date?
    private var _lastSuccessTime: Date?

    /// Consecutive failures before opening the circuit
    private let failureThreshold = 5
    /// Seconds to wait before trying again (half-open)
    private let resetTimeout: TimeInterval = 30
    /// Consecutive successes in half-open needed to close
    private let halfOpenSuccessThreshold = 2
    private var _halfOpenSuccessCount = 0

    var state: State {
        lock.lock(); defer { lock.unlock() }
        if _state == .open, let last = _lastFailureTime,
           Date().timeIntervalSince(last) >= resetTimeout {
            _state = .halfOpen
            _halfOpenSuccessCount = 0
        }
        return _state
    }

    /// Returns true if the request is allowed to proceed
    func allowRequest() -> Bool {
        let current = state // triggers open→halfOpen transition
        switch current {
        case .closed: return true
        case .halfOpen: return true   // allow probe request
        case .open: return false      // fail fast
        }
    }

    func recordSuccess() {
        lock.lock(); defer { lock.unlock() }
        _lastSuccessTime = Date()
        if _state == .halfOpen {
            _halfOpenSuccessCount += 1
            if _halfOpenSuccessCount >= halfOpenSuccessThreshold {
                _state = .closed
                _failureCount = 0
            }
        } else {
            _failureCount = 0
        }
    }

    func recordFailure() {
        lock.lock(); defer { lock.unlock() }
        _failureCount += 1
        _lastFailureTime = Date()
        if _failureCount >= failureThreshold {
            _state = .open
            _halfOpenSuccessCount = 0
        }
    }

    /// Current stats for observability
    var diagnostics: (state: State, failures: Int, lastFailure: Date?) {
        lock.lock(); defer { lock.unlock() }
        return (_state, _failureCount, _lastFailureTime)
    }
}

// MARK: - Base API Client

/// Base class providing shared HTTP functionality for all domain API clients
class BaseAPIClient {
    private let logger: Logger
    private let logCategory: String
    private let circuitBreaker = CircuitBreaker.shared

    var baseURL: String {
        NetworkConfig.shared.baseURL
    }

    var apiKey: String? {
        KeychainManager.shared.apiKey
    }

    // MARK: - Retry Configuration

    private let maxRetries = 3
    private let initialRetryDelay: TimeInterval = 0.5
    private let retryMultiplier: Double = 2.0

    init(category: String) {
        self.logCategory = category
        self.logger = Logger(subsystem: "com.nexus.app", category: category)
    }

    // MARK: - Network Layer

    /// Compute retry delay with exponential backoff + jitter to prevent thundering herd
    private func retryDelay(attempt: Int) -> TimeInterval {
        let exponential = initialRetryDelay * pow(retryMultiplier, Double(attempt - 1))
        let jitter = exponential * Double.random(in: 0.5...1.5) // ±50% jitter
        return min(jitter, 30.0) // cap at 30s
    }

    func performRequest(_ request: URLRequest, attempt: Int = 1) async throws -> (Data, HTTPURLResponse) {
        // Rate limiter: prevent spam
        let method = request.httpMethod ?? "GET"
        let endpoint = request.url?.path ?? "unknown"
        guard await RateLimiter.shared.shouldAllow(endpoint: endpoint, method: method) else {
            throw APIError.rateLimited
        }

        // Circuit breaker: fail fast if backend is known-down
        guard circuitBreaker.allowRequest() else {
            let diag = circuitBreaker.diagnostics
            logger.warning("Circuit breaker OPEN (\(diag.failures) failures). Failing fast.")
            throw APIError.serverError(503)
        }

        let startTime = Date()

        do {
            logger.debug("[\(attempt)/\(self.maxRetries)] \(request.httpMethod ?? "GET") \(request.url?.path ?? "")")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let duration = Date().timeIntervalSince(startTime)
            logger.debug("[\(httpResponse.statusCode)] Response received in \(String(format: "%.2f", duration))s")

            #if DEBUG
            logResponse(data, response: httpResponse)
            #endif

            // Retry on 5xx server errors
            if httpResponse.statusCode >= 500, attempt < maxRetries {
                circuitBreaker.recordFailure()
                let delay = retryDelay(attempt: attempt)
                logger.warning("Server error \(httpResponse.statusCode), retrying in \(String(format: "%.1f", delay))s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(request, attempt: attempt + 1)
            }

            // 5xx on final attempt — record failure but don't retry
            if httpResponse.statusCode >= 500 {
                circuitBreaker.recordFailure()
                throw APIError.serverError(httpResponse.statusCode)
            }

            // Handle 409 Conflict specially — not really an error
            if httpResponse.statusCode == 409 {
                // Let ConflictResolver process this
                Task {
                    let httpMethod = request.httpMethod ?? "POST"
                    let path = request.url?.path ?? "unknown"
                    _ = await ConflictResolver.shared.handleConflictResponse(data, for: "\(httpMethod) \(path)")
                }
                // Still throw for error handling, but it will be classified as clientError
                throw APIError.serverError(409)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                // 4xx errors don't affect the circuit breaker
                throw APIError.serverError(httpResponse.statusCode)
            }

            circuitBreaker.recordSuccess()
            return (data, httpResponse)
        } catch let error as APIError {
            logger.error("API error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            circuitBreaker.recordFailure()
            // Retry on network errors with jitter
            if attempt < maxRetries {
                let delay = retryDelay(attempt: attempt)
                logger.warning("Retrying in \(String(format: "%.1f", delay))s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(request, attempt: attempt + 1)
            }
            throw error
        }
    }

    #if DEBUG
    private func logResponse(_ data: Data, response: HTTPURLResponse) {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            logger.debug("Response body:\n\(prettyString)")
        } else if let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Response body: \(responseString)")
        }
    }
    #endif

    // MARK: - Generic HTTP Methods

    /// Generic GET request
    func get<T: Decodable>(_ endpoint: String, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, _) = try await performRequest(request)
        return try decoder.decode(T.self, from: data)
    }

    /// Generic POST request
    func post<Body: Encodable, Response: Decodable>(
        _ endpoint: String,
        body: Body,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, _) = try await performRequest(request)
        return try decoder.decode(Response.self, from: data)
    }

    /// Convenience POST that returns NexusResponse
    func post<T: Encodable>(_ endpoint: String, body: T) async throws -> NexusResponse {
        try await post(endpoint, body: body, decoder: JSONDecoder())
    }

    /// Generic PUT request
    func put<Body: Encodable, Response: Decodable>(
        _ endpoint: String,
        body: Body,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, _) = try await performRequest(request)
        return try decoder.decode(Response.self, from: data)
    }

    /// Generic DELETE request
    func delete<T: Decodable>(_ endpoint: String, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, _) = try await performRequest(request)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Safe URL Parameter Builder

    /// Builds a path with properly encoded query parameters using URLComponents
    /// Prevents URL injection attacks by properly encoding parameter values
    /// - Parameters:
    ///   - base: The base path (e.g., "/webhook/nexus-food-search")
    ///   - query: Dictionary of query parameter key-value pairs
    /// - Returns: A complete path with query string (e.g., "/webhook/nexus-food-search?q=encoded&limit=10")
    func buildPath(_ base: String, query: [String: String]) -> String {
        guard !query.isEmpty else { return base }
        var components = URLComponents()
        components.path = base
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // Return path + query string (no scheme/host since BaseAPIClient.get/delete adds those)
        return components.path + "?" + (components.percentEncodedQuery ?? "")
    }

    // MARK: - Dubai Timezone Helpers

    static let dubaiTimeZone = Constants.Dubai.timeZone

    static func dubaiISO8601String(from date: Date) -> String {
        Constants.Dubai.iso8601String(from: date)
    }

    static func dubaiDateString(from date: Date) -> String {
        Constants.Dubai.dateString(from: date)
    }

    // MARK: - Finance Date Decoder

    static let financeDateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601Standard = ISO8601DateFormatter()
        iso8601Standard.formatOptions = [.withInternetDateTime]
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = Constants.Dubai.timeZone

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = iso8601WithFractional.date(from: dateString) {
                return date
            }
            if let date = iso8601Standard.date(from: dateString) {
                return date
            }
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }()
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case offline
    case rateLimited
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .offline:
            return "No network connection"
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Nexus Error

enum NexusError: LocalizedError {
    case network(URLError)
    case api(APIError)
    case validation(ValidationError)
    case offline(queuedItemCount: Int)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .api(let error):
            return error.localizedDescription
        case .validation(let error):
            return "Invalid input: \(error.localizedDescription)"
        case .offline(let count):
            return "Offline - \(count) items queued for sync"
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .offline:
            return "Your data will sync automatically when you're back online"
        case .network:
            return "Check your internet connection and try again"
        case .validation:
            return "Please check your input and try again"
        case .api(.serverError(let code)) where code >= 500:
            return "The server is experiencing issues. Please try again later"
        case .api(.serverError(let code)) where code == 401:
            return "Please check your API key in settings"
        default:
            return "Please try again"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .network, .api(.serverError), .offline:
            return true
        case .validation, .api(.invalidURL), .api(.invalidResponse):
            return false
        default:
            return true
        }
    }
}
