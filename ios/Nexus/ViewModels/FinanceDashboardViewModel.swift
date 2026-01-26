import Foundation
import SwiftUI
import Combine

/// ViewModel for the redesigned Finance Dashboard
/// Uses a single unified endpoint: GET /app/finance
@MainActor
class FinanceDashboardViewModel: ObservableObject {
    // MARK: - Published State

    @Published var dashboard: FinanceDashboardDTO?
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var isOffline = false
    @Published var queuedOperations = 0

    // MARK: - Services

    private let api = NexusAPI.shared
    private let cache = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var loadTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var currency: String {
        dashboard?.meta.currency ?? AppSettings.shared.defaultCurrency
    }

    var todaySpend: Double {
        dashboard?.today.spent ?? 0
    }

    var todayTransactionCount: Int {
        dashboard?.today.transactionCount ?? 0
    }

    var todayVsYesterday: Double? {
        dashboard?.today.vsYesterday
    }

    var isTodayUnusual: Bool {
        dashboard?.today.isUnusual ?? false
    }

    var monthSpend: Double {
        dashboard?.month.spent ?? 0
    }

    var monthIncome: Double {
        dashboard?.month.income ?? 0
    }

    var monthNet: Double {
        dashboard?.month.net ?? 0
    }

    var monthBudget: Double? {
        dashboard?.month.budget
    }

    var monthBudgetUsedPercent: Double? {
        dashboard?.month.budgetUsedPercent
    }

    var monthBudgetRemaining: Double? {
        dashboard?.month.budgetRemaining
    }

    var daysRemaining: Int {
        dashboard?.month.daysRemaining ?? 0
    }

    var topCategories: [FinanceCategoryDTO] {
        Array(dashboard?.month.categories.prefix(3) ?? [])
    }

    var recentTransactions: [FinanceTransactionDTO] {
        Array(dashboard?.recent.prefix(5) ?? [])
    }

    var insight: FinanceInsightDTO? {
        dashboard?.insight
    }

    // MARK: - State Helpers

    var hasData: Bool {
        dashboard != nil
    }

    var staleMinutes: Int? {
        guard let lastUpdated = lastUpdated else { return nil }
        let minutes = Int(-lastUpdated.timeIntervalSinceNow / 60)
        return minutes > 5 ? minutes : nil
    }

    // MARK: - Initialization

    init() {
        loadFromCache()
        updateQueuedCount()
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Data Loading

    func loadDashboard() {
        loadTask?.cancel()
        isLoading = dashboard == nil  // Only show loading if no cached data
        errorMessage = nil

        loadTask = Task {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            // Check connectivity
            guard networkMonitor.isConnected else {
                isOffline = true
                isLoading = false
                if dashboard == nil {
                    errorMessage = "No connection. Check your network."
                }
                return
            }

            isOffline = false

            do {
                // TODO: Replace with actual unified endpoint
                // For now, use the existing finance summary endpoint
                let response = try await api.fetchFinanceSummary()

                if response.success, let data = response.data {
                    // Transform existing response to new DTO format
                    dashboard = transformToDTO(from: data, transactions: data.recentTransactions ?? [])
                    lastUpdated = Date()
                    errorMessage = nil

                    // Cache the transformed data
                    saveToCache()
                }

                isLoading = false
            } catch {
                isLoading = false
                if dashboard == nil {
                    errorMessage = "Failed to load finance data"
                }
                #if DEBUG
                print("Finance dashboard fetch failed: \(error)")
                #endif
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        loadDashboard()

        // Wait for the load task to complete
        await loadTask?.value
        isRefreshing = false
    }

    // MARK: - Cache

    private func loadFromCache() {
        // Try to load cached finance data
        let cached = cache.loadFinanceCache()
        if let summary = cached.summary, let transactions = cached.transactions {
            dashboard = transformToDTO(from: nil, transactions: transactions, summary: summary)
            // Get timestamp from cache manager
            if let age = cache.getCacheAge(forKey: "finance_summary") {
                lastUpdated = Date().addingTimeInterval(-age)
            }
        }
    }

    private func saveToCache() {
        // The existing cache system handles this via FinanceViewModel
        // For now, we don't duplicate caching
    }

    // MARK: - Transform Legacy Data to DTO

    private func transformToDTO(
        from data: FinanceResponseData?,
        transactions: [Transaction],
        summary: FinanceSummary? = nil
    ) -> FinanceDashboardDTO {
        let source = summary ?? FinanceSummary()
        let totalSpent = data?.totalSpent ?? source.totalSpent

        // Build categories from breakdown
        let categoryBreakdown = data?.categoryBreakdown ?? source.categoryBreakdown
        let categories: [FinanceCategoryDTO] = categoryBreakdown
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { key, value in
                FinanceCategoryDTO(
                    name: key.capitalized,
                    spent: abs(value),
                    budget: source.budgets.first { $0.category.lowercased() == key.lowercased() }?.budgetAmount,
                    percentOfTotal: totalSpent > 0 ? (abs(value) / totalSpent) * 100 : 0,
                    icon: categoryIcon(for: key)
                )
            }

        // Calculate budget totals
        let totalBudget = source.budgets.reduce(0) { $0 + $1.budgetAmount }
        let budgetUsedPercent = totalBudget > 0 ? (totalSpent / totalBudget) * 100 : nil

        // Calculate today's spend from recent transactions
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayTransactions = transactions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let todaySpend = todayTransactions.reduce(0.0) { $0 + abs($1.amount) }

        // Calculate days remaining in month
        let daysRemaining = calendar.range(of: .day, in: .month, for: Date())!.count -
                           calendar.component(.day, from: Date())

        // Transform transactions to DTO
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Dubai")

        let recentDTO: [FinanceTransactionDTO] = transactions.prefix(10).compactMap { tx in
            guard let id = tx.id else { return nil }
            return FinanceTransactionDTO(
                id: id,
                date: tx.date,
                time: dateFormatter.string(from: tx.date),
                merchant: tx.merchantName,
                amount: tx.amount,
                category: tx.category,
                source: tx.source
            )
        }

        // Generate insight
        let insight = generateInsight(totalSpent: totalSpent, categories: categories, budgets: source.budgets)

        return FinanceDashboardDTO(
            meta: FinanceMeta(
                generatedAt: Date(),
                timezone: "Asia/Dubai",
                currency: data?.currency ?? AppSettings.shared.defaultCurrency
            ),
            today: FinanceTodayDTO(
                spent: todaySpend,
                transactionCount: todayTransactions.count,
                vsYesterday: nil,  // Would need historical data
                vsAverage7d: nil,
                isUnusual: false
            ),
            month: FinanceMonthDTO(
                spent: totalSpent,
                income: 0,  // Would need income tracking
                budget: totalBudget > 0 ? totalBudget : nil,
                budgetUsedPercent: budgetUsedPercent,
                daysRemaining: daysRemaining,
                projectedTotal: nil,
                categories: categories
            ),
            recent: recentDTO,
            insight: insight
        )
    }

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "grocery", "groceries": return "cart.fill"
        case "restaurant", "food", "dining": return "fork.knife"
        case "transport", "transportation": return "car.fill"
        case "utilities": return "house.fill"
        case "entertainment": return "tv.fill"
        case "health", "medical": return "heart.fill"
        case "shopping": return "bag.fill"
        default: return "creditcard.fill"
        }
    }

    private func generateInsight(
        totalSpent: Double,
        categories: [FinanceCategoryDTO],
        budgets: [Budget]
    ) -> FinanceInsightDTO? {
        // Check for over-budget categories
        for category in categories {
            if let budget = category.budget, category.spent > budget {
                return FinanceInsightDTO(
                    type: "over_budget",
                    title: "\(category.name) over budget",
                    detail: "You've spent \(formatCurrency(category.spent - budget, currency: currency)) more than budgeted.",
                    icon: "exclamationmark.triangle.fill",
                    severity: .warning
                )
            }
        }

        // Check for high spending category
        if let topCategory = categories.first, topCategory.percentOfTotal > 40 {
            return FinanceInsightDTO(
                type: "category_high",
                title: "\(topCategory.name) dominates spending",
                detail: "\(Int(topCategory.percentOfTotal))% of your spending is on \(topCategory.name.lowercased()).",
                icon: topCategory.icon ?? "chart.pie.fill",
                severity: .info
            )
        }

        // Default: budget status
        if let budgetPercent = monthBudgetUsedPercent {
            if budgetPercent < 50 && daysRemaining < 15 {
                return FinanceInsightDTO(
                    type: "budget_good",
                    title: "Spending on track",
                    detail: "You've used \(Int(budgetPercent))% of your budget with \(daysRemaining) days left.",
                    icon: "checkmark.circle.fill",
                    severity: .info
                )
            }
        }

        return nil
    }

    // MARK: - Actions

    func updateQueuedCount() {
        queuedOperations = OfflineQueue.shared.getQueueCount()
    }

    /// Trigger manual SMS import
    func triggerImport() async {
        do {
            _ = try await api.triggerSMSImport()
            await refresh()
        } catch {
            #if DEBUG
            print("SMS import trigger failed: \(error)")
            #endif
        }
    }
}
