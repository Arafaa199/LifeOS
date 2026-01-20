import Foundation
import Combine

class NexusAPI: ObservableObject {
    static let shared = NexusAPI()

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
    }

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "nexusAPIKey")
    }

    // MARK: - Logging Methods

    func logFood(_ text: String) async throws -> NexusResponse {
        let request = FoodLogRequest(text: text)
        return try await post("/webhook/nexus-food", body: request)
    }

    func logWater(amountML: Int) async throws -> NexusResponse {
        let request = WaterLogRequest(amount_ml: amountML)
        return try await post("/webhook/nexus-water", body: request)
    }

    func logWeight(kg: Double) async throws -> NexusResponse {
        let request = WeightLogRequest(weight_kg: kg)
        return try await post("/webhook/nexus-weight", body: request)
    }

    func logMood(mood: Int, energy: Int, notes: String? = nil) async throws -> NexusResponse {
        let request = MoodLogRequest(mood: mood, energy: energy, notes: notes)
        return try await post("/webhook/nexus-mood", body: request)
    }

    func logUniversal(_ text: String) async throws -> NexusResponse {
        let request = UniversalLogRequest(text: text)
        return try await post("/webhook/nexus-universal", body: request)
    }

    // MARK: - Finance Methods

    func logExpense(_ text: String) async throws -> FinanceResponse {
        let request = QuickExpenseRequest(text: text)
        return try await postFinance("/webhook/nexus-expense", body: request)
    }

    func addTransaction(_ merchantName: String, amount: Double, category: String? = nil, notes: String? = nil) async throws -> FinanceResponse {
        let request = AddTransactionRequest(
            merchantName: merchantName,
            amount: amount,
            category: category,
            notes: notes,
            date: ISO8601DateFormatter().string(from: Date())
        )
        return try await postFinance("/webhook/nexus-transaction", body: request)
    }

    func updateTransaction(id: Int, merchantName: String, amount: Double, category: String, notes: String?, date: Date) async throws -> FinanceResponse {
        let request = UpdateTransactionRequest(
            id: id,
            merchantName: merchantName,
            amount: amount,
            category: category,
            notes: notes,
            date: ISO8601DateFormatter().string(from: date)
        )
        return try await postFinance("/webhook/nexus-update-transaction", body: request)
    }

    func deleteTransaction(id: Int) async throws -> NexusResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-delete-transaction?id=\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NexusResponse.self, from: data)
    }

    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async throws -> FinanceResponse {
        let request = AddIncomeRequest(
            source: source,
            amount: amount,
            category: category,
            notes: notes,
            date: ISO8601DateFormatter().string(from: date),
            isRecurring: isRecurring
        )
        return try await postFinance("/webhook/nexus-income", body: request)
    }

    func fetchFinanceSummary() async throws -> FinanceResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-finance-summary") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601DateFormatter first (handles 'Z' suffix properly)
            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: dateString) {
                return date
            }

            // Fallback to simple date format (YYYY-MM-DD)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return try decoder.decode(FinanceResponse.self, from: data)
    }

    func triggerSMSImport() async throws -> NexusResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-trigger-import") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NexusResponse.self, from: data)
    }

    // MARK: - Budget Methods

    func setBudget(category: String, amount: Double) async throws -> BudgetResponse {
        let request = SetBudgetRequest(category: category, amount: amount)
        return try await postBudget("/webhook/nexus-set-budget", body: request)
    }

    func fetchBudgets() async throws -> BudgetsResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-budgets") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(BudgetsResponse.self, from: data)
    }

    func deleteBudget(id: Int) async throws -> NexusResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-budget?id=\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NexusResponse.self, from: data)
    }

    func getSpendingInsights(summary: String) async throws -> InsightsResponse {
        let request = InsightsRequest(summary: summary)
        return try await postInsights("/webhook/nexus-insights", body: request)
    }

    func fetchMonthlyTrends(months: Int) async throws -> MonthlyTrendsResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-monthly-trends?months=\(months)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MonthlyTrendsResponse.self, from: data)
    }

    private func postBudget<T: Encodable>(_ endpoint: String, body: T) async throws -> BudgetResponse {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(BudgetResponse.self, from: data)
    }

    private func postInsights<T: Encodable>(_ endpoint: String, body: T) async throws -> InsightsResponse {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(InsightsResponse.self, from: data)
    }

    // MARK: - Network Layer

    func postFinance<T: Encodable>(_ endpoint: String, body: T) async throws -> FinanceResponse {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(FinanceResponse.self, from: data)
    }

    func post<T: Encodable>(_ endpoint: String, body: T) async throws -> NexusResponse {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NexusResponse.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case offline

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
        }
    }
}

// MARK: - Dashboard Data Fetch

struct DailySummaryResponse: Codable {
    let success: Bool
    let data: DailySummaryData?
}

struct DailySummaryData: Codable {
    let date: String
    let calories: Int
    let protein: Double
    let water: Int
    let weight: Double?
    let mood: Int?
    let energy: Int?
    let logs: [LogEntryData]?
}

struct LogEntryData: Codable {
    let id: String?
    let type: String
    let description: String
    let timestamp: String
    let calories: Int?
    let protein: Double?
}

extension NexusAPI {
    // Fetch today's summary from the backend
    func fetchDailySummary(for date: Date = Date()) async throws -> DailySummaryResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        guard let url = URL(string: "\(baseURL)/webhook/nexus-summary?date=\(dateString)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(DailySummaryResponse.self, from: data)
    }
}
