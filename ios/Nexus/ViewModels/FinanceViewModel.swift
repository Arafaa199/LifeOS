import Foundation
import SwiftUI
import Combine
import os

@MainActor
class FinanceViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "finance")
    @Published var summary = FinanceSummary()
    @Published var recentTransactions: [Transaction] = []
    @Published var recurringItems: [RecurringItem] = []
    @Published var errorMessage: String?

    // MARK: - Planned Features (API not yet implemented)
    @Published var activeDebts: [Debt] = []
    @Published var wishlistItems: [WishlistItem] = []
    @Published var cashflowProjection: [CashflowMonth] = []
    @Published var pendingMessage: String?  // Shows when item queued locally but not synced
    @Published var queuedCount = 0
    @Published var lastUpdated: Date?

    // Tracks in-flight CRUD operations (not sync — sync state comes from coordinator)
    @Published private(set) var operationInProgress = false

    private let api: NexusAPI
    private let cache: CacheManager
    private let networkMonitor: NetworkMonitor
    private let coordinator: SyncCoordinator
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Sync State (derived from coordinator)

    var isLoading: Bool {
        operationInProgress || coordinator.domainStates[.finance]?.isSyncing == true
    }

    var isOffline: Bool {
        coordinator.domainStates[.finance]?.lastError != nil
    }

    // MARK: - Dashboard-Sourced Properties

    var financeFreshness: DomainFreshness? {
        coordinator.dashboardPayload?.dataFreshness?.finance
    }

    var serverInsights: [RankedInsight] {
        let all = coordinator.dashboardPayload?.dailyInsights?.rankedInsights ?? []
        return all.filter { insight in
            let t = insight.type.lowercased()
            return t.hasPrefix("spending") || t.hasPrefix("budget") || t.hasPrefix("finance") || t.hasPrefix("pattern")
        }
    }

    var monthlyObligations: Double {
        recurringItems
            .filter { $0.isExpense && $0.isActive }
            .reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var upcomingBills: [RecurringItem] {
        recurringItems
            .filter { $0.isExpense && $0.isActive }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    var recurringIncome: [RecurringItem] {
        recurringItems
            .filter { $0.isIncome && $0.isActive }
    }

    init(
        api: NexusAPI? = nil,
        cache: CacheManager? = nil,
        networkMonitor: NetworkMonitor? = nil,
        coordinator: SyncCoordinator? = nil
    ) {
        self.api = api ?? NexusAPI.shared
        self.cache = cache ?? CacheManager.shared
        self.networkMonitor = networkMonitor ?? NetworkMonitor.shared
        self.coordinator = coordinator ?? SyncCoordinator.shared
        loadFromCache()
        subscribeToCoordinator()
        updateQueuedCount()
    }

    func updateQueuedCount() {
        queuedCount = OfflineQueue.shared.getQueueCount()
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Coordinator Subscription

    private func subscribeToCoordinator() {
        coordinator.$financeSummaryResult
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                self?.applyFinanceResponse(response)
            }
            .store(in: &cancellables)

        // Subscribe to finance-specific state changes only
        // (isLoading, isOffline) trigger view updates.
        coordinator.financeStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func applyFinanceResponse(_ response: FinanceResponse) {
        guard response.success, let data = response.data else { return }

        if let totalSpent = data.totalSpent {
            summary.totalSpent = abs(totalSpent)
        }
        if let grocerySpent = data.grocerySpent {
            summary.grocerySpent = abs(grocerySpent)
        }
        if let eatingOutSpent = data.eatingOutSpent {
            summary.eatingOutSpent = abs(eatingOutSpent)
        }
        if let currency = data.currency {
            summary.currency = currency
        }
        if let transactions = data.recentTransactions {
            recentTransactions = transactions.map { $0.normalized() }
        }
        if let budgets = data.budgets {
            summary.budgets = budgets
        }
        if let categoryBreakdown = data.categoryBreakdown {
            summary.categoryBreakdown = categoryBreakdown
        }
        if let totalIncome = data.totalIncome {
            summary.totalIncome = abs(totalIncome)
        } else if let dashboardIncome = coordinator.dashboardPayload?.todayFacts?.incomeTotal {
            summary.totalIncome = abs(dashboardIncome)
        }

        cache.saveFinanceSummary(summary, transactions: recentTransactions)
        if !summary.budgets.isEmpty {
            cache.saveBudgets(summary.budgets)
        }

        lastUpdated = Date()
        errorMessage = nil
        operationInProgress = false
    }

    private func loadFromCache() {
        let cached = cache.loadFinanceCache()
        if let summary = cached.summary {
            self.summary = summary
        }
        if let transactions = cached.transactions {
            self.recentTransactions = transactions
        }
    }

    func loadFinanceSummary() {
        // Delegate to coordinator — the Combine subscription handles the response.
        // isLoading is computed from coordinator sync state.
        Task {
            await coordinator.sync(.finance)
            if coordinator.domainStates[.finance]?.lastError != nil {
                errorMessage = "Could not fetch latest data. Showing cached data."
            }
        }
        loadRecurringItems()
    }

    /// Logs a quick expense from natural language. Returns true on success.
    @discardableResult
    func logExpense(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }

        operationInProgress = true
        errorMessage = nil

        let (response, result) = await api.logExpenseOffline(text)

        if case .failed(let error) = result {
            errorMessage = "Error: \(error.localizedDescription)"
            operationInProgress = false
            return false
        }

        let generator = UINotificationFeedbackGenerator()

        if case .queued = result {
            // Item queued locally - NOT confirmed on server yet
            // Don't update totals, don't show success haptic
            updateQueuedCount()
            generator.notificationOccurred(.warning)  // Different haptic for "pending"
            pendingMessage = "Saved locally - will sync when online"
            operationInProgress = false
            return true  // Form can dismiss, but user knows it's pending
        }

        // Only update UI totals when server confirms
        if let response = response, response.success {
            if let data = response.data {
                if let totalSpent = data.totalSpent {
                    summary.totalSpent = totalSpent
                }
                if let transaction = data.transaction {
                    let normalizedTransaction = transaction.normalized()
                    recentTransactions.insert(normalizedTransaction, at: 0)
                    if recentTransactions.count > 20 {
                        recentTransactions = Array(recentTransactions.prefix(20))
                    }

                    if normalizedTransaction.isGrocery {
                        summary.grocerySpent += abs(normalizedTransaction.amount)
                    }
                    if normalizedTransaction.isRestaurant {
                        summary.eatingOutSpent += abs(normalizedTransaction.amount)
                    }
                }
            }
            generator.notificationOccurred(.success)  // Success haptic only for confirmed
        }

        // Refresh in background
        Task { loadFinanceSummary() }

        operationInProgress = false
        return true
    }

    func refresh() async {
        await coordinator.sync(.finance)
        if coordinator.domainStates[.finance]?.lastError != nil {
            errorMessage = "Could not fetch latest data. Showing cached data."
        }
    }

    func triggerSMSImport() async {
        operationInProgress = true
        errorMessage = nil

        do {
            let response = try await api.triggerSMSImport()

            if response.success {
                // Success feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Reload transactions
                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to trigger import"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        operationInProgress = false
    }

    /// Adds a manual transaction. Returns true on success (including offline queue).
    /// Only sets errorMessage on actual failure, not for offline queue.
    @discardableResult
    func addManualTransaction(merchantName: String, amount: Double, category: String, notes: String?, date: Date) async -> Bool {
        operationInProgress = true
        errorMessage = nil

        let (response, result) = await api.addTransactionOffline(
            merchant: merchantName,
            amount: amount,
            category: category,
            notes: notes,
            date: date
        )

        if case .failed(let error) = result {
            errorMessage = "Error: \(error.localizedDescription)"
            operationInProgress = false
            return false
        }

        let generator = UINotificationFeedbackGenerator()

        if case .queued = result {
            // Item queued locally - NOT confirmed on server yet
            updateQueuedCount()
            generator.notificationOccurred(.warning)  // Different haptic for "pending"
            pendingMessage = "Saved locally - will sync when online"
            operationInProgress = false
            return true
        }

        // Only update summary when server confirms
        let spentAmount = abs(amount)
        summary.totalSpent += spentAmount
        if category == "Grocery" {
            summary.grocerySpent += spentAmount
        } else if category == "Restaurant" {
            summary.eatingOutSpent += spentAmount
        }

        generator.notificationOccurred(.success)

        // Refresh in background, don't block success
        Task { loadFinanceSummary() }

        operationInProgress = false
        return true
    }

    func updateTransaction(id: Int, merchantName: String, amount: Double, category: String, notes: String?, date: Date) async {
        operationInProgress = true
        errorMessage = nil

        do {
            let response = try await api.updateTransaction(
                id: id,
                merchantName: merchantName,
                amount: amount,
                category: category,
                notes: notes,
                date: date
            )

            if response.success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to update transaction"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        operationInProgress = false
    }

    func deleteTransaction(id: Int) async {
        operationInProgress = true
        errorMessage = nil

        do {
            let response = try await api.deleteTransaction(id: id)

            if response.success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Remove from local list
                recentTransactions.removeAll { $0.id == id }

                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to delete transaction"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        operationInProgress = false
    }

    // MARK: - Income Tracking

    /// Adds income. Returns true on success (including offline queue).
    /// Income amounts are always stored as positive values.
    @discardableResult
    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async -> Bool {
        operationInProgress = true
        errorMessage = nil

        // Income is always positive
        let incomeAmount = abs(amount)

        let (_, result) = await api.addIncomeOffline(
            source: source,
            amount: incomeAmount,
            category: category,
            notes: notes,
            date: date,
            isRecurring: isRecurring
        )

        if case .failed(let error) = result {
            errorMessage = "Error: \(error.localizedDescription)"
            operationInProgress = false
            return false
        }

        let generator = UINotificationFeedbackGenerator()

        if case .queued = result {
            // Item queued locally - NOT confirmed on server yet
            updateQueuedCount()
            generator.notificationOccurred(.warning)  // Different haptic for "pending"
            pendingMessage = "Saved locally - will sync when online"
            operationInProgress = false
            return true
        }

        generator.notificationOccurred(.success)

        // Refresh in background, don't block success
        Task { loadFinanceSummary() }

        operationInProgress = false
        return true
    }

    // MARK: - Recurring Transactions Detection

    func detectRecurringTransactions() -> [RecurringPattern] {
        var patterns: [RecurringPattern] = []

        // Group by merchant
        let grouped = Dictionary(grouping: recentTransactions, by: { $0.merchantName })

        for (merchant, transactions) in grouped where transactions.count >= 3 {
            // Check if transactions occur at regular intervals
            let sortedDates = transactions.map { $0.date }.sorted()

            var intervals: [TimeInterval] = []
            for i in 1..<sortedDates.count {
                intervals.append(sortedDates[i].timeIntervalSince(sortedDates[i-1]))
            }

            // Check if intervals are similar (within 7 days tolerance)
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            let isRecurring = intervals.allSatisfy { abs($0 - avgInterval) < 7 * 24 * 60 * 60 }

            if isRecurring {
                let avgAmount = transactions.map { abs($0.amount) }.reduce(0, +) / Double(transactions.count)

                let frequency: RecurringPattern.Frequency
                let days = avgInterval / (24 * 60 * 60)

                if days < 10 {
                    frequency = .weekly
                } else if days < 35 {
                    frequency = .monthly
                } else if days < 100 {
                    frequency = .quarterly
                } else {
                    frequency = .yearly
                }

                patterns.append(RecurringPattern(
                    merchant: merchant,
                    amount: avgAmount,
                    frequency: frequency,
                    count: transactions.count,
                    lastDate: sortedDates.last ?? Date()
                ))
            }
        }

        return patterns.sorted { $0.amount > $1.amount }
    }

    // MARK: - Transaction Corrections

    func createCorrection(
        transactionId: Int,
        amount: Double?,
        category: String?,
        merchantName: String?,
        date: Date?,
        reason: CorrectionReason,
        notes: String?
    ) async -> Bool {
        operationInProgress = true
        errorMessage = nil

        let request = CreateCorrectionRequest(
            transactionId: transactionId,
            amount: amount,
            currency: nil,
            category: category,
            merchantName: merchantName,
            date: date.map { Constants.Dubai.iso8601String(from: $0) },
            reason: reason.rawValue,
            notes: notes,
            createdBy: "ios"
        )

        do {
            let response = try await api.createCorrection(request)

            if response.success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                await refresh()
                operationInProgress = false
                return true
            } else {
                errorMessage = response.message ?? "Failed to create correction"
                operationInProgress = false
                return false
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            operationInProgress = false
            return false
        }
    }

    func deactivateCorrection(correctionId: Int) async {
        operationInProgress = true
        errorMessage = nil

        do {
            let response = try await api.deactivateCorrection(correctionId: correctionId)

            if response.success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to revert correction"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        operationInProgress = false
    }

    // MARK: - Recurring Items

    func loadRecurringItems() {
        Task {
            do {
                let response = try await api.fetchRecurringItems()
                if response.success, let items = response.data {
                    recurringItems = items
                } else {
                    logger.warning("Failed to load recurring items: empty response")
                }
            } catch {
                logger.warning("Failed to load recurring items: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func createRecurringItem(_ request: CreateRecurringItemRequest) async -> Bool {
        do {
            let response = try await api.createRecurringItem(request)
            if response.success {
                loadRecurringItems()
                return true
            }
            errorMessage = "Failed to create recurring item"
        } catch {
            logger.error("Create recurring item failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        return false
    }

    @discardableResult
    func updateRecurringItem(_ request: UpdateRecurringItemRequest) async -> Bool {
        do {
            let response = try await api.updateRecurringItem(request)
            if response.success {
                loadRecurringItems()
                return true
            }
            errorMessage = "Failed to update recurring item"
        } catch {
            logger.error("Update recurring item failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        return false
    }

    @discardableResult
    func deleteRecurringItem(id: Int) async -> Bool {
        do {
            let response = try await api.deleteRecurringItem(id: id)
            if response.success {
                recurringItems.removeAll { $0.id == id }
                return true
            }
            errorMessage = "Failed to delete recurring item"
        } catch {
            logger.error("Delete recurring item failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        return false
    }

    // MARK: - Duplicate Detection

    /// Finds potential duplicate transactions (same merchant/amount within ±1 day)
    func detectDuplicateTransactions() -> [[Transaction]] {
        var duplicateGroups: [[Transaction]] = []

        let sorted = recentTransactions.sorted { $0.date < $1.date }
        var processed = Set<Int>()

        for (index, transaction) in sorted.enumerated() {
            guard let id = transaction.id, !processed.contains(id) else { continue }

            var group: [Transaction] = [transaction]
            processed.insert(id)

            // Look for duplicates within ±1 day
            for otherIndex in (index + 1)..<sorted.count {
                let other = sorted[otherIndex]
                guard let otherId = other.id, !processed.contains(otherId) else { continue }

                // Check if within 1 day
                let dayDifference = abs(transaction.date.timeIntervalSince(other.date)) / (24 * 60 * 60)
                guard dayDifference <= 1 else { continue }

                // Check if same merchant and amount
                let sameMerchant = transaction.merchantName.lowercased() == other.merchantName.lowercased()
                let sameAmount = abs(transaction.amount - other.amount) < 0.01

                if sameMerchant && sameAmount {
                    group.append(other)
                    processed.insert(otherId)
                }
            }

            // Only include groups with actual duplicates (2+ transactions)
            if group.count > 1 {
                duplicateGroups.append(group)
            }
        }

        return duplicateGroups.sorted { $0.first?.date ?? Date() > $1.first?.date ?? Date() }
    }
}

struct RecurringPattern: Identifiable {
    let id = UUID()
    let merchant: String
    let amount: Double
    let frequency: Frequency
    let count: Int
    let lastDate: Date

    enum Frequency: String {
        case weekly = "Weekly"
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"
    }
}

// MARK: - Planned Feature Models (API not yet implemented)

struct Debt: Identifiable, Codable {
    let id: Int
    let name: String
    let totalAmount: Double
    let remainingAmount: Double
    let monthlyPayment: Double?
    let interestRate: Double?
    let dueDate: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case totalAmount = "total_amount"
        case remainingAmount = "remaining_amount"
        case monthlyPayment = "monthly_payment"
        case interestRate = "interest_rate"
        case dueDate = "due_date"
        case isActive = "is_active"
    }
}

struct CreateDebtRequest: Codable {
    let name: String
    let totalAmount: Double
    let remainingAmount: Double
    let monthlyPayment: Double?
    let interestRate: Double?
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case totalAmount = "total_amount"
        case remainingAmount = "remaining_amount"
        case monthlyPayment = "monthly_payment"
        case interestRate = "interest_rate"
        case dueDate = "due_date"
    }
}

struct WishlistItem: Identifiable, Codable {
    let id: Int
    let name: String
    let estimatedCost: Double
    let priority: Int?
    let notes: String?
    let targetDate: String?
    let url: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, priority, notes, url, status
        case estimatedCost = "estimated_cost"
        case targetDate = "target_date"
    }

    var statusIcon: String {
        switch status?.lowercased() {
        case "purchased": return "checkmark.circle.fill"
        case "saved": return "bookmark.fill"
        default: return "star"
        }
    }
}

struct CreateWishlistRequest: Codable {
    let name: String
    let estimatedCost: Double
    let currency: String?
    let priority: Int?
    let targetDate: String?
    let url: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, priority, notes, url, currency
        case estimatedCost = "estimated_cost"
        case targetDate = "target_date"
    }
}

struct CashflowMonth: Identifiable, Codable {
    var id: String { month }
    let month: String
    let projectedIncome: Double
    let projectedExpenses: Double
    let projectedNet: Double
    let cumulativeSavings: Double?
    let activeDebtsRemaining: Double?

    enum CodingKeys: String, CodingKey {
        case month
        case projectedIncome = "projected_income"
        case projectedExpenses = "projected_expenses"
        case projectedNet = "projected_net"
        case cumulativeSavings = "cumulative_savings"
        case activeDebtsRemaining = "active_debts_remaining"
    }

    var isPositiveNet: Bool { projectedNet >= 0 }

    var monthLabel: String {
        // Parse "2026-02" format and return "Feb 2026"
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let monthNum = Int(parts[1]) else { return month }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let monthName = formatter.shortMonthSymbols[monthNum - 1]
        return "\(monthName) \(parts[0])"
    }
}
