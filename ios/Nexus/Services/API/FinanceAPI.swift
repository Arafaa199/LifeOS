import Foundation
import os

// MARK: - Finance API Client

/// Handles all finance-related endpoints: transactions, budgets, recurring items, categories, rules
class FinanceAPI: BaseAPIClient {
    static let shared = FinanceAPI()
    private let logger = Logger(subsystem: "com.nexus.app", category: "finance-api")

    private init() {
        super.init(category: "finance-api")
    }

    // MARK: - POST with Finance Decoder

    private func postFinance<T: Encodable>(_ endpoint: String, body: T) async throws -> FinanceResponse {
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

    // MARK: - Transactions

    func logExpense(_ text: String) async throws -> FinanceResponse {
        let request = QuickExpenseRequest(text: text)
        return try await postFinance("/webhook/nexus-expense", body: request)
    }

    func logExpenseWithClientId(_ text: String, clientId: String) async throws -> FinanceResponse {
        let request = QuickExpenseRequest(text: text, clientId: clientId)
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

    // MARK: - Income

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

    // MARK: - Finance Summary

    func fetchFinanceSummary() async throws -> FinanceResponse {
        return try await get("/webhook/nexus-finance-summary", decoder: Self.financeDateDecoder)
    }

    func triggerSMSImport() async throws -> NexusResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-trigger-import", body: EmptyBody())
    }

    // MARK: - Budgets

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

    func createBudget(_ request: CreateBudgetRequest) async throws -> SingleItemResponse<Budget> {
        return try await post("/webhook/nexus-budgets", body: request, decoder: Self.financeDateDecoder)
    }

    // MARK: - Insights & Trends

    func getSpendingInsights(summary: String) async throws -> InsightsResponse {
        let request = InsightsRequest(summary: summary)
        return try await post("/webhook/nexus-insights", body: request, decoder: JSONDecoder())
    }

    func fetchMonthlyTrends(months: Int) async throws -> MonthlyTrendsResponse {
        return try await get("/webhook/nexus-monthly-trends?months=\(months)")
    }

    // MARK: - Installments

    func fetchInstallments() async throws -> InstallmentsResponse {
        try await get("/webhook/nexus-installments", decoder: Self.financeDateDecoder)
    }

    // MARK: - Categories

    func fetchCategories() async throws -> CategoriesResponse {
        return try await get("/webhook/nexus-categories", decoder: Self.financeDateDecoder)
    }

    func createCategory(_ request: CreateCategoryRequest) async throws -> SingleItemResponse<Category> {
        return try await post("/webhook/nexus-categories", body: request, decoder: Self.financeDateDecoder)
    }

    func deleteCategory(id: Int) async throws -> DeleteResponse {
        return try await delete("/webhook/nexus-categories?id=\(id)")
    }

    // MARK: - Recurring Items

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

    // MARK: - Matching Rules

    func fetchMatchingRules() async throws -> MatchingRulesResponse {
        return try await get("/webhook/nexus-rules", decoder: Self.financeDateDecoder)
    }

    func createMatchingRule(_ request: CreateMatchingRuleRequest) async throws -> SingleItemResponse<MatchingRule> {
        return try await post("/webhook/nexus-rules", body: request, decoder: Self.financeDateDecoder)
    }

    func deleteMatchingRule(id: Int) async throws -> DeleteResponse {
        return try await delete("/webhook/nexus-rules?id=\(id)")
    }

    // MARK: - Transaction Corrections

    func createCorrection(_ request: CreateCorrectionRequest) async throws -> CorrectionResponse {
        return try await post("/webhook/nexus-create-correction", body: request, decoder: JSONDecoder())
    }

    func deactivateCorrection(correctionId: Int) async throws -> DeleteResponse {
        let request = DeactivateCorrectionRequest(correctionId: correctionId)
        return try await post("/webhook/nexus-deactivate-correction", body: request, decoder: JSONDecoder())
    }

    // MARK: - Receipts

    func fetchReceipts(limit: Int = 50) async throws -> ReceiptsResponse {
        return try await get("/webhook/nexus-receipts?limit=\(limit)")
    }
}
