import Foundation
import os

// MARK: - Base API Client

/// Base class providing shared HTTP functionality for all domain API clients
class BaseAPIClient {
    private let logger: Logger
    private let logCategory: String

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

    func performRequest(_ request: URLRequest, attempt: Int = 1) async throws -> (Data, HTTPURLResponse) {
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
                let delay = initialRetryDelay * pow(retryMultiplier, Double(attempt - 1))
                logger.warning("Server error \(httpResponse.statusCode), retrying in \(delay)s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(request, attempt: attempt + 1)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            return (data, httpResponse)
        } catch let error as APIError {
            logger.error("API error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            // Retry on network errors
            if attempt < maxRetries {
                let delay = initialRetryDelay * pow(retryMultiplier, Double(attempt - 1))
                logger.warning("Retrying in \(delay)s...")
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
