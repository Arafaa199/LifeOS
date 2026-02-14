import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "api")

// MARK: - NexusAPI Facade
//
// This class now serves as a facade that delegates to domain-specific API clients.
// New code should use the domain clients directly (DashboardAPI, FinanceAPI, etc.)
// This facade maintains backwards compatibility during the migration period.

class NexusAPI: ObservableObject {
    static let shared = NexusAPI()

    // Domain clients
    private let dashboard = DashboardAPI.shared
    private let finance = FinanceAPI.shared
    private let health = HealthAPI.shared
    private let nutrition = NutritionAPI.shared
    private let documents = DocumentsAPI.shared
    private let habits = HabitsAPI.shared

    // Backwards compatibility properties
    private var baseURL: String { NetworkConfig.shared.baseURL }
    private var apiKey: String? { KeychainManager.shared.apiKey }

    // MARK: - Nutrition (delegate to NutritionAPI)

    func logFood(_ text: String, foodId: Int? = nil, mealType: String? = nil) async throws -> NexusResponse {
        try await nutrition.logFood(text, foodId: foodId, mealType: mealType)
    }

    func searchFoods(query: String, limit: Int = 10) async throws -> FoodSearchResponse {
        try await nutrition.searchFoods(query: query, limit: limit)
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodSearchResponse {
        try await nutrition.lookupBarcode(barcode)
    }

    func fetchNutritionHistory(date: String? = nil) async throws -> NutritionHistoryResponse {
        try await nutrition.fetchNutritionHistory(date: date)
    }

    func startFast() async throws -> FastingResponse {
        try await nutrition.startFast()
    }

    func breakFast() async throws -> FastingResponse {
        try await nutrition.breakFast()
    }

    func getFastingStatus() async throws -> FastingResponse {
        try await nutrition.getFastingStatus()
    }

    func fetchPendingMealConfirmations(date: Date? = nil) async throws -> [InferredMeal] {
        try await nutrition.fetchPendingMealConfirmations(date: date)
    }

    func confirmMeal(mealDate: String, mealTime: String, mealType: String, action: String) async throws -> NexusResponse {
        try await nutrition.confirmMeal(mealDate: mealDate, mealTime: mealTime, mealType: mealType, action: action)
    }

    // MARK: - Health (delegate to HealthAPI)

    func logWeight(kg: Double) async throws -> NexusResponse {
        try await health.logWeight(kg: kg)
    }

    func logMood(mood: Int, energy: Int, notes: String? = nil) async throws -> NexusResponse {
        try await health.logMood(mood: mood, energy: energy, notes: notes)
    }

    func logUniversal(_ text: String) async throws -> NexusResponse {
        try await health.logUniversal(text)
    }

    func fetchSupplements() async throws -> SupplementsResponse {
        try await health.fetchSupplements()
    }

    func createSupplement(_ request: SupplementCreateRequest) async throws -> SupplementUpsertResponse {
        try await health.createSupplement(request)
    }

    func updateSupplement(id: Int, request: SupplementCreateRequest) async throws -> SupplementUpsertResponse {
        try await health.updateSupplement(id: id, request: request)
    }

    func logSupplementDose(_ request: SupplementLogRequest) async throws -> SupplementLogResponse {
        try await health.logSupplementDose(request)
    }

    func deactivateSupplement(id: Int) async throws -> NexusResponse {
        try await health.deactivateSupplement(id: id)
    }

    func fetchWorkouts() async throws -> WorkoutsResponse {
        try await health.fetchWorkouts()
    }

    func logWorkout(_ request: WorkoutLogRequest) async throws -> WorkoutLogResponse {
        try await health.logWorkout(request)
    }

    func createMedication(_ request: MedicationCreateRequest) async throws -> MedicationCreateResponse {
        try await health.createMedication(request)
    }

    // MARK: - Finance (delegate to FinanceAPI)

    func logExpense(_ text: String) async throws -> FinanceResponse {
        try await finance.logExpense(text)
    }

    func addTransaction(_ merchantName: String, amount: Double, category: String? = nil, notes: String? = nil) async throws -> FinanceResponse {
        try await finance.addTransaction(merchantName, amount: amount, category: category, notes: notes)
    }

    func updateTransaction(id: Int, merchantName: String, amount: Double, category: String, notes: String?, date: Date) async throws -> FinanceResponse {
        try await finance.updateTransaction(id: id, merchantName: merchantName, amount: amount, category: category, notes: notes, date: date)
    }

    func deleteTransaction(id: Int) async throws -> NexusResponse {
        try await finance.deleteTransaction(id: id)
    }

    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async throws -> FinanceResponse {
        try await finance.addIncome(source: source, amount: amount, category: category, notes: notes, date: date, isRecurring: isRecurring)
    }

    func refreshWHOOP() async throws -> WhoopRefreshResponse {
        try await dashboard.refreshWHOOP()
    }

    func logExpenseWithClientId(_ text: String, clientId: String) async throws -> FinanceResponse {
        try await finance.logExpenseWithClientId(text, clientId: clientId)
    }

    func addTransactionWithClientId(merchant: String, amount: Double, category: String?, notes: String? = nil, date: Date = Date(), clientId: String) async throws -> FinanceResponse {
        try await finance.addTransactionWithClientId(merchant: merchant, amount: amount, category: category, notes: notes, date: date, clientId: clientId)
    }

    func addIncomeWithClientId(source: String, amount: Double, category: String, notes: String? = nil, date: Date = Date(), isRecurring: Bool = false, clientId: String) async throws -> FinanceResponse {
        try await finance.addIncomeWithClientId(source: source, amount: amount, category: category, notes: notes, date: date, isRecurring: isRecurring, clientId: clientId)
    }

    func fetchFinanceSummary() async throws -> FinanceResponse {
        try await finance.fetchFinanceSummary()
    }

    func fetchTransactions(offset: Int = 0, limit: Int = 50, startDate: String? = nil, endDate: String? = nil) async throws -> FinanceResponse {
        try await finance.fetchTransactions(offset: offset, limit: limit, startDate: startDate, endDate: endDate)
    }

    func triggerSMSImport() async throws -> NexusResponse {
        try await finance.triggerSMSImport()
    }

    func setBudget(category: String, amount: Double) async throws -> BudgetResponse {
        try await finance.setBudget(category: category, amount: amount)
    }

    func fetchBudgets() async throws -> BudgetsResponse {
        try await finance.fetchBudgets()
    }

    func deleteBudget(id: Int) async throws -> NexusResponse {
        try await finance.deleteBudget(id: id)
    }

    func getSpendingInsights(summary: String) async throws -> InsightsResponse {
        try await finance.getSpendingInsights(summary: summary)
    }

    func fetchMonthlyTrends(months: Int) async throws -> MonthlyTrendsResponse {
        try await finance.fetchMonthlyTrends(months: months)
    }

    func fetchSyncStatus() async throws -> SyncStatusResponse {
        try await dashboard.fetchSyncStatus()
    }

    func fetchInstallments() async throws -> InstallmentsResponse {
        try await finance.fetchInstallments()
    }

    func fetchCategories() async throws -> CategoriesResponse {
        try await finance.fetchCategories()
    }

    func createCategory(_ request: CreateCategoryRequest) async throws -> SingleItemResponse<Category> {
        try await finance.createCategory(request)
    }

    func deleteCategory(id: Int) async throws -> DeleteResponse {
        try await finance.deleteCategory(id: id)
    }

    func fetchRecurringItems() async throws -> RecurringItemsResponse {
        try await finance.fetchRecurringItems()
    }

    func createRecurringItem(_ request: CreateRecurringItemRequest) async throws -> SingleItemResponse<RecurringItem> {
        try await finance.createRecurringItem(request)
    }

    func updateRecurringItem(_ request: UpdateRecurringItemRequest) async throws -> SingleItemResponse<RecurringItem> {
        try await finance.updateRecurringItem(request)
    }

    func deleteRecurringItem(id: Int) async throws -> DeleteResponse {
        try await finance.deleteRecurringItem(id: id)
    }

    func fetchMatchingRules() async throws -> MatchingRulesResponse {
        try await finance.fetchMatchingRules()
    }

    func createMatchingRule(_ request: CreateMatchingRuleRequest) async throws -> SingleItemResponse<MatchingRule> {
        try await finance.createMatchingRule(request)
    }

    func deleteMatchingRule(id: Int) async throws -> DeleteResponse {
        try await finance.deleteMatchingRule(id: id)
    }

    func createBudget(_ request: CreateBudgetRequest) async throws -> SingleItemResponse<Budget> {
        try await finance.createBudget(request)
    }

    func fetchReceipts(offset: Int = 0, limit: Int = 50) async throws -> ReceiptsResponse {
        try await finance.fetchReceipts(offset: offset, limit: limit)
    }

    func createCorrection(_ request: CreateCorrectionRequest) async throws -> CorrectionResponse {
        try await finance.createCorrection(request)
    }

    func deactivateCorrection(correctionId: Int) async throws -> DeleteResponse {
        try await finance.deactivateCorrection(correctionId: correctionId)
    }

    // MARK: - Habits (delegate to HabitsAPI)

    func fetchHabits() async throws -> HabitsResponse {
        try await habits.fetchHabits()
    }

    func completeHabit(_ request: LogHabitRequest) async throws -> HabitResponse {
        try await habits.completeHabit(request)
    }

    func createHabit(_ request: CreateHabitRequest) async throws -> HabitResponse {
        try await habits.createHabit(request)
    }

    func deleteHabit(habitId: Int) async throws -> HabitDeleteResponse {
        try await habits.deleteHabit(id: habitId)
    }

    // MARK: - Documents/Reminders (delegate to DocumentsAPI)

    func fetchReminders(start: String? = nil, end: String? = nil) async throws -> RemindersDisplayResponse {
        try await documents.fetchReminders(start: start, end: end)
    }

    func createReminder(_ request: ReminderCreateRequest) async throws -> ReminderCreateResponse {
        try await documents.createReminder(request)
    }

    func updateReminder(_ request: ReminderUpdateRequest) async throws -> ReminderUpdateResponse {
        try await documents.updateReminder(request)
    }

    func deleteReminder(id: Int? = nil, reminderId: String? = nil) async throws -> ReminderDeleteResponse {
        try await documents.deleteReminder(id: id, reminderId: reminderId)
    }

    func toggleReminderCompletion(reminderId: String, isCompleted: Bool) async throws -> ReminderUpdateResponse {
        try await documents.toggleReminderCompletion(reminderId: reminderId, isCompleted: isCompleted)
    }

    func searchNotes(query: String? = nil, tag: String? = nil, limit: Int = 50) async throws -> NotesSearchResponse {
        try await documents.searchNotes(query: query, tag: tag, limit: limit)
    }

    // MARK: - Dashboard (delegate to DashboardAPI)

    func fetchDailySummary(for date: Date = Date()) async throws -> DailySummaryResponse {
        try await dashboard.fetchDailySummary(for: date)
    }

    func fetchSleepData(for date: Date = Date()) async throws -> SleepResponse {
        try await dashboard.fetchSleepData(for: date)
    }

    func fetchSleepHistory(days: Int = 7) async throws -> SleepHistoryResponse {
        try await dashboard.fetchSleepHistory(days: days)
    }

    func fetchHealthTimeseries(days: Int = 30) async throws -> HealthTimeseriesResponse {
        try await dashboard.fetchHealthTimeseries(days: days)
    }

    func fetchHomeStatus() async throws -> HomeStatusResponse {
        try await dashboard.fetchHomeStatus()
    }

    func controlDevice(entityId: String, action: HomeAction, brightness: Int? = nil) async throws -> HomeControlResponse {
        try await dashboard.controlDevice(entityId: entityId, action: action, brightness: brightness)
    }

    func logMusicEvents(_ events: [ListeningEvent]) async throws -> MusicEventsResponse {
        try await dashboard.logMusicEvents(events)
    }

    func fetchMusicHistory(limit: Int = 20) async throws -> MusicHistoryResponse {
        try await dashboard.fetchMusicHistory(limit: limit)
    }

    // MARK: - Backwards Compatibility: Direct HTTP Access
    // These are exposed for callers that need raw HTTP access (e.g., SyncCoordinator.syncDocuments, OfflineQueue)

    func get<T: Decodable>(_ endpoint: String) async throws -> T {
        try await documents.get(endpoint)
    }

    func post<T: Encodable>(_ endpoint: String, body: T) async throws -> NexusResponse {
        try await health.post(endpoint, body: body)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ endpoint: String,
        body: Body,
        decoder: JSONDecoder
    ) async throws -> Response {
        try await health.post(endpoint, body: body, decoder: decoder)
    }

    func delete<T: Decodable>(_ endpoint: String) async throws -> T {
        try await documents.delete(endpoint)
    }

    // MARK: - Dubai Timezone Helpers (static, for backwards compatibility)

    static let dubaiTimeZone = Constants.Dubai.timeZone

    static func dubaiISO8601String(from date: Date) -> String {
        Constants.Dubai.iso8601String(from: date)
    }

    static func dubaiDateString(from date: Date) -> String {
        Constants.Dubai.dateString(from: date)
    }
}
