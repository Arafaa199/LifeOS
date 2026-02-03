import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "api")

class NexusAPI: ObservableObject {
    static let shared = NexusAPI()

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
    }

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "nexusAPIKey")
    }

    // MARK: - Logging Methods

    /// Logs a food entry to the Nexus API
    ///
    /// This method sends a natural language description of food consumed to the API,
    /// which will parse it and return nutritional information.
    ///
    /// - Parameter text: Natural language description of the food consumed
    /// - Returns: Response containing nutritional information including calories and protein
    /// - Throws: ``APIError`` if the request fails
    ///
    /// ## Example
    /// ```swift
    /// let response = try await api.logFood("2 scrambled eggs and whole wheat toast")
    /// print("Calories: \(response.data?.calories ?? 0)")
    /// ```
    func logFood(_ text: String, foodId: Int? = nil, mealType: String? = nil) async throws -> NexusResponse {
        let request = FoodLogRequest(text: text, food_id: foodId, meal_type: mealType)
        return try await post("/webhook/nexus-food-log", body: request)
    }

    func searchFoods(query: String, limit: Int = 10) async throws -> FoodSearchResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/webhook/nexus-food-search?q=\(encoded)&limit=\(limit)")
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodSearchResponse {
        return try await get("/webhook/nexus-food-search?barcode=\(barcode)")
    }

    func fetchNutritionHistory(date: String? = nil) async throws -> NutritionHistoryResponse {
        var endpoint = "/webhook/nexus-nutrition-history"
        if let date = date {
            endpoint += "?date=\(date)"
        }
        return try await get(endpoint)
    }

    // MARK: - Fasting

    func startFast() async throws -> FastingResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-fast-start", body: EmptyBody())
    }

    func breakFast() async throws -> FastingResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-fast-break", body: EmptyBody())
    }

    func getFastingStatus() async throws -> FastingResponse {
        return try await get("/webhook/nexus-fast-status")
    }

    /// Logs water intake in milliliters
    ///
    /// - Parameter amountML: Amount of water in milliliters (1-10,000)
    /// - Returns: Response containing total water intake for the day
    /// - Throws: ``ValidationError`` if amount is invalid, ``APIError`` if request fails
    func logWater(amountML: Int) async throws -> NexusResponse {
        let request = try WaterLogRequest(amount_ml: amountML)
        return try await post("/webhook/nexus-water", body: request)
    }

    /// Logs body weight in kilograms
    ///
    /// - Parameter kg: Weight in kilograms (1-500)
    /// - Returns: Response confirming weight was logged
    /// - Throws: ``ValidationError`` if weight is invalid, ``APIError`` if request fails
    func logWeight(kg: Double) async throws -> NexusResponse {
        let request = try WeightLogRequest(weight_kg: kg)
        return try await post("/webhook/nexus-weight", body: request)
    }

    /// Logs mood and energy levels
    ///
    /// - Parameters:
    ///   - mood: Mood rating from 1 (lowest) to 10 (highest)
    ///   - energy: Energy level from 1 (lowest) to 10 (highest)
    ///   - notes: Optional notes about the mood/energy state
    /// - Returns: Response confirming mood was logged
    /// - Throws: ``ValidationError`` if mood or energy is out of range, ``APIError`` if request fails
    func logMood(mood: Int, energy: Int, notes: String? = nil) async throws -> NexusResponse {
        let request = try MoodLogRequest(mood: mood, energy: energy, notes: notes)
        return try await post("/webhook/nexus-mood", body: request)
    }

    /// Logs a universal entry that will be automatically categorized by the API
    ///
    /// - Parameter text: Natural language description of the activity or event
    /// - Returns: Response from the API
    /// - Throws: ``APIError`` if the request fails
    func logUniversal(_ text: String) async throws -> NexusResponse {
        let request = UniversalLogRequest(text: text)
        return try await post("/webhook/nexus-universal", body: request)
    }

    // MARK: - Installments (BNPL)

    func fetchInstallments() async throws -> InstallmentsResponse {
        try await get("/webhook/nexus-installments", decoder: Self.financeDateDecoder)
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
            date: Self.dubaiISO8601String(from: Date())
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
            date: Self.dubaiISO8601String(from: date)
        )
        return try await postFinance("/webhook/nexus-update-transaction", body: request)
    }

    func deleteTransaction(id: Int) async throws -> NexusResponse {
        return try await delete("/webhook/nexus-delete-transaction?id=\(id)")
    }

    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async throws -> FinanceResponse {
        let request = AddIncomeRequest(
            source: source,
            amount: amount,
            category: category,
            notes: notes,
            date: Self.dubaiISO8601String(from: date),
            isRecurring: isRecurring
        )
        return try await postFinance("/webhook/nexus-income", body: request)
    }

    // MARK: - WHOOP Refresh

    func refreshWHOOP() async throws -> WhoopRefreshResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-whoop-refresh", body: EmptyBody(), decoder: JSONDecoder())
    }

    // MARK: - Finance Methods with Client ID (for idempotency)

    func logExpenseWithClientId(_ text: String, clientId: String) async throws -> FinanceResponse {
        let request = QuickExpenseRequest(text: text, clientId: clientId)
        return try await postFinance("/webhook/nexus-expense", body: request)
    }

    func addTransactionWithClientId(merchant: String, amount: Double, category: String?, notes: String? = nil, date: Date = Date(), clientId: String) async throws -> FinanceResponse {
        let request = AddTransactionRequest(
            merchantName: merchant,
            amount: amount,
            category: category,
            notes: notes,
            date: Self.dubaiISO8601String(from: date),
            clientId: clientId
        )
        return try await postFinance("/webhook/nexus-transaction", body: request)
    }

    func addIncomeWithClientId(source: String, amount: Double, category: String, notes: String? = nil, date: Date = Date(), isRecurring: Bool = false, clientId: String) async throws -> FinanceResponse {
        let request = AddIncomeRequest(
            source: source,
            amount: amount,
            category: category,
            notes: notes,
            date: Self.dubaiISO8601String(from: date),
            isRecurring: isRecurring,
            clientId: clientId
        )
        return try await postFinance("/webhook/nexus-income", body: request)
    }

    func fetchFinanceSummary() async throws -> FinanceResponse {
        return try await get("/webhook/nexus-finance-summary", decoder: Self.financeDateDecoder)
    }

    func triggerSMSImport() async throws -> NexusResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-trigger-import", body: EmptyBody())
    }

    // MARK: - Budget Methods

    func setBudget(category: String, amount: Double) async throws -> BudgetResponse {
        let request = SetBudgetRequest(category: category, amount: amount)
        return try await post("/webhook/nexus-set-budget", body: request, decoder: JSONDecoder())
    }

    func fetchBudgets() async throws -> BudgetsResponse {
        return try await get("/webhook/nexus-budgets")
    }

    func deleteBudget(id: Int) async throws -> NexusResponse {
        return try await delete("/webhook/nexus-budget?id=\(id)")
    }

    func getSpendingInsights(summary: String) async throws -> InsightsResponse {
        let request = InsightsRequest(summary: summary)
        return try await post("/webhook/nexus-insights", body: request, decoder: JSONDecoder())
    }

    func fetchMonthlyTrends(months: Int) async throws -> MonthlyTrendsResponse {
        return try await get("/webhook/nexus-monthly-trends?months=\(months)")
    }

    // MARK: - LifeOS Summary Methods

    func fetchFinanceDailySummary(date: Date? = nil) async throws -> FinanceDailySummaryResponse {
        var endpoint = "/webhook/nexus-daily-summary"
        if let date = date {
            endpoint += "?date=\(Self.dubaiDateString(from: date))"
        }
        return try await get(endpoint, decoder: Self.financeDateDecoder)
    }

    func fetchWeeklyReport(weekStart: Date? = nil) async throws -> WeeklyReportResponse {
        var endpoint = "/webhook/nexus-weekly-report"
        if let weekStart = weekStart {
            endpoint += "?week_start=\(Self.dubaiDateString(from: weekStart))"
        }
        return try await get(endpoint, decoder: Self.financeDateDecoder)
    }

    func fetchSystemHealth() async throws -> SystemHealthResponse {
        return try await get("/webhook/nexus-system-health", decoder: Self.financeDateDecoder)
    }

    func fetchSyncStatus() async throws -> SyncStatusResponse {
        return try await get("/webhook/nexus-sync-status")
    }

    func refreshSummaries() async throws -> NexusResponse {
        guard let url = URL(string: "\(baseURL)/webhook/nexus-refresh-summary") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, _) = try await performRequest(request)
        return try JSONDecoder().decode(NexusResponse.self, from: data)
    }

    // MARK: - Meal Confirmation Methods

    func fetchPendingMealConfirmations(date: Date? = nil) async throws -> [InferredMeal] {
        var endpoint = "/webhook/nexus-pending-meals"
        if let date = date {
            endpoint += "?date=\(Self.dubaiDateString(from: date))"
        }

        struct Response: Codable {
            let meals: [InferredMeal]
        }

        let response: Response = try await get(endpoint)
        return response.meals
    }

    func confirmMeal(mealDate: String, mealTime: String, mealType: String, action: String) async throws -> NexusResponse {
        struct Request: Codable {
            let meal_date: String
            let meal_time: String
            let meal_type: String
            let action: String
        }

        let request = Request(
            meal_date: mealDate,
            meal_time: mealTime,
            meal_type: mealType,
            action: action
        )

        return try await post("/webhook/nexus-meal-confirmation", body: request)
    }

    // MARK: - Finance Planning Methods

    func fetchCategories() async throws -> CategoriesResponse {
        return try await get("/webhook/nexus-categories", decoder: Self.financeDateDecoder)
    }

    func createCategory(_ request: CreateCategoryRequest) async throws -> SingleItemResponse<Category> {
        return try await post("/webhook/nexus-categories", body: request, decoder: Self.financeDateDecoder)
    }

    func deleteCategory(id: Int) async throws -> DeleteResponse {
        return try await delete("/webhook/nexus-categories?id=\(id)")
    }

    func fetchRecurringItems() async throws -> RecurringItemsResponse {
        return try await get("/webhook/nexus-recurring", decoder: Self.financeDateDecoder)
    }

    func createRecurringItem(_ request: CreateRecurringItemRequest) async throws -> SingleItemResponse<RecurringItem> {
        return try await post("/webhook/nexus-recurring", body: request, decoder: Self.financeDateDecoder)
    }

    func updateRecurringItem(_ request: UpdateRecurringItemRequest) async throws -> SingleItemResponse<RecurringItem> {
        return try await post("/webhook/nexus-recurring-update", body: request, decoder: Self.financeDateDecoder)
    }

    func deleteRecurringItem(id: Int) async throws -> DeleteResponse {
        return try await delete("/webhook/nexus-recurring?id=\(id)")
    }

    func fetchMatchingRules() async throws -> MatchingRulesResponse {
        return try await get("/webhook/nexus-rules", decoder: Self.financeDateDecoder)
    }

    func createMatchingRule(_ request: CreateMatchingRuleRequest) async throws -> SingleItemResponse<MatchingRule> {
        return try await post("/webhook/nexus-rules", body: request, decoder: Self.financeDateDecoder)
    }

    func deleteMatchingRule(id: Int) async throws -> DeleteResponse {
        return try await delete("/webhook/nexus-rules?id=\(id)")
    }

    func createBudget(_ request: CreateBudgetRequest) async throws -> SingleItemResponse<Budget> {
        return try await post("/webhook/nexus-budgets", body: request, decoder: Self.financeDateDecoder)
    }

    // MARK: - Transaction Corrections

    func createCorrection(_ request: CreateCorrectionRequest) async throws -> CorrectionResponse {
        return try await post("/webhook/nexus-create-correction", body: request, decoder: JSONDecoder())
    }

    func deactivateCorrection(correctionId: Int) async throws -> DeleteResponse {
        let request = DeactivateCorrectionRequest(correctionId: correctionId)
        return try await post("/webhook/nexus-deactivate-correction", body: request, decoder: JSONDecoder())
    }

    // MARK: - Network Layer

    private let maxRetries = 3
    private let initialRetryDelay: TimeInterval = 0.5
    private let retryMultiplier: Double = 2.0

    private func performRequest(_ request: URLRequest, attempt: Int = 1) async throws -> (Data, HTTPURLResponse) {
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

            // Retry on 5xx server errors or specific transient errors
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
            // Retry on network errors (timeout, connection lost, etc.)
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

    /// Generic POST method for all API calls
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

    // Convenience wrappers for specific response types
    func post<T: Encodable>(_ endpoint: String, body: T) async throws -> NexusResponse {
        try await post(endpoint, body: body, decoder: JSONDecoder())
    }

    /// POST for finance operations — decode failures are propagated as errors.
    func postFinance<T: Encodable>(_ endpoint: String, body: T) async throws -> FinanceResponse {
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

        do {
            return try Self.financeDateDecoder.decode(FinanceResponse.self, from: data)
        } catch {
            logger.warning("Finance decode failed: \(error.localizedDescription)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.debug("Response was: \(responseString)")
            }
            throw APIError.decodingError
        }
    }
    
    // MARK: - URL Building Helper
    
    private func buildURL(endpoint: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        return url
    }

    // MARK: - Generic GET Helper

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

    // MARK: - Generic DELETE Helper

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

    // MARK: - Dubai Timezone Helpers (delegates to Constants.Dubai)

    static let dubaiTimeZone = Constants.Dubai.timeZone

    static func dubaiISO8601String(from date: Date) -> String {
        Constants.Dubai.iso8601String(from: date)
    }

    static func dubaiDateString(from date: Date) -> String {
        Constants.Dubai.dateString(from: date)
    }

    private static var financeDateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601.date(from: dateString) {
                return date
            }

            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: dateString) {
                return date
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = Constants.Dubai.timeZone
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
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

// MARK: - Comprehensive Error Handling

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
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = dubaiTimeZone
        return formatter
    }

    func fetchDailySummary(for date: Date = Date()) async throws -> DailySummaryResponse {
        let dateString = Self.dateFormatter.string(from: date)
        return try await get("/webhook/nexus-summary?date=\(dateString)")
    }

    func fetchSleepData(for date: Date = Date()) async throws -> SleepResponse {
        let dateString = Self.dateFormatter.string(from: date)
        return try await get("/webhook/nexus-sleep?date=\(dateString)")
    }

    func fetchSleepHistory(days: Int = 7) async throws -> SleepHistoryResponse {
        return try await get("/webhook/nexus-sleep-history?days=\(days)")
    }

    func fetchHealthTimeseries(days: Int = 30) async throws -> HealthTimeseriesResponse {
        return try await get("/webhook/nexus-health-timeseries?days=\(days)")
    }
}

// MARK: - Sleep/Recovery Models

struct SleepResponse: Codable {
    let success: Bool
    let data: SleepData?
}

struct SleepHistoryResponse: Codable {
    let success: Bool
    let data: [SleepData]?
}

struct SleepData: Codable, Identifiable {
    var id: String { date }
    let date: String
    let sleep: SleepMetrics?
    let recovery: RecoveryMetrics?
}

struct SleepMetrics: Codable {
    let timeInBedMin: Int?
    let awakeMin: Int?
    let lightSleepMin: Int?
    let deepSleepMin: Int?
    let remSleepMin: Int?
    let sleepEfficiency: Double?
    let sleepConsistency: Int?
    let sleepPerformance: Int?
    let sleepNeededMin: Int?
    let sleepDebtMin: Int?
    let cycles: Int?
    let disturbances: Int?
    let respiratoryRate: Double?

    enum CodingKeys: String, CodingKey {
        case timeInBedMin = "time_in_bed_min"
        case awakeMin = "awake_min"
        case lightSleepMin = "light_sleep_min"
        case deepSleepMin = "deep_sleep_min"
        case remSleepMin = "rem_sleep_min"
        case sleepEfficiency = "sleep_efficiency"
        case sleepConsistency = "sleep_consistency"
        case sleepPerformance = "sleep_performance"
        case sleepNeededMin = "sleep_needed_min"
        case sleepDebtMin = "sleep_debt_min"
        case cycles
        case disturbances
        case respiratoryRate = "respiratory_rate"
    }

    var totalSleepMin: Int {
        (lightSleepMin ?? 0) + (deepSleepMin ?? 0) + (remSleepMin ?? 0)
    }
}

struct RecoveryMetrics: Codable {
    let recoveryScore: Int?
    let hrv: Double?
    let rhr: Int?
    let spo2: Double?
    let skinTemp: Double?

    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case hrv = "hrv_rmssd"
        case rhr
        case spo2
        case skinTemp = "skin_temp"
    }
}

// MARK: - Health Timeseries Models

// MARK: - WHOOP Refresh Response

struct WhoopRefreshResponse: Codable {
    let success: Bool
    let message: String?
    let sensorsFound: Int?
    let recovery: Double?
    let daily_facts_refreshed: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message, sensorsFound, recovery
        case daily_facts_refreshed
    }
}

struct HealthTimeseriesResponse: Codable {
    let success: Bool
    let data: [DailyHealthPoint]?
    let count: Int?
}

struct DailyHealthPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let hrv: Double?
    let rhr: Int?
    let recovery: Int?
    let sleepMinutes: Int?
    let sleepQuality: Int?
    let strain: Double?
    let steps: Int?
    let weight: Double?
    let activeEnergy: Int?
    let coverage: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case hrv
        case rhr
        case recovery
        case sleepMinutes = "sleep_minutes"
        case sleepQuality = "sleep_quality"
        case strain
        case steps
        case weight
        case activeEnergy = "active_energy"
        case coverage
    }
}
