import Foundation
import SwiftUI
import Combine

@MainActor
class FinanceViewModel: ObservableObject {
    @Published var summary = FinanceSummary()
    @Published var recentTransactions: [Transaction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOffline = false
    @Published var queuedCount = 0
    @Published var lastUpdated: Date?

    private let api = NexusAPI.shared
    private let cache = CacheManager.shared
    private let dashboardService = DashboardService.shared
    private let networkMonitor = NetworkMonitor.shared
    private let coordinator = SyncCoordinator.shared
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dashboard-Sourced Properties

    var financeFreshness: DomainFreshness? {
        dashboardService.loadCached()?.payload.dataFreshness?.finance
    }

    var serverInsights: [RankedInsight] {
        let all = dashboardService.loadCached()?.payload.dailyInsights?.rankedInsights ?? []
        return all.filter { insight in
            let t = insight.type.lowercased()
            return t.hasPrefix("spending") || t.hasPrefix("budget") || t.hasPrefix("finance") || t.hasPrefix("pattern")
        }
    }

    init() {
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
        } else if let dashboardIncome = dashboardService.loadCached()?.payload.todayFacts.incomeTotal {
            summary.totalIncome = abs(dashboardIncome)
        }

        cache.saveFinanceSummary(summary, transactions: recentTransactions)
        if !summary.budgets.isEmpty {
            cache.saveBudgets(summary.budgets)
        }

        lastUpdated = Date()
        errorMessage = nil
        isLoading = false
        isOffline = false
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
        isLoading = true
        // Delegate to coordinator — the Combine subscription handles the response
        Task {
            await coordinator.sync(.finance)
            // If coordinator didn't produce a result (e.g. offline), mark offline
            if coordinator.domainStates[.finance]?.lastError != nil {
                isOffline = true
                errorMessage = "Could not fetch latest data. Showing cached data."
            }
            isLoading = false
        }
    }

    /// Logs a quick expense from natural language. Returns true on success.
    @discardableResult
    func logExpense(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.logExpenseOffline(text)

            if response.success {
                // Queued offline is still a success
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    // Note: NOT setting errorMessage - this is a success state
                } else if let data = response.data {
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

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Refresh in background
                Task { loadFinanceSummary() }

                isLoading = false
                return true
            } else {
                errorMessage = response.message ?? "Failed to log expense"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    func refresh() async {
        isLoading = true
        await coordinator.sync(.finance)
        if coordinator.domainStates[.finance]?.lastError != nil {
            isOffline = true
            errorMessage = "Could not fetch latest data. Showing cached data."
        }
        isLoading = false
    }

    func triggerSMSImport() async {
        isLoading = true
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

        isLoading = false
    }

    /// Adds a manual transaction. Returns true on success (including offline queue).
    /// Only sets errorMessage on actual failure, not for offline queue.
    @discardableResult
    func addManualTransaction(merchantName: String, amount: Double, category: String, notes: String?, date: Date) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.addTransactionOffline(
                merchant: merchantName,
                amount: amount,
                category: category
            )

            if response.success {
                // Queued offline is still a success - don't set errorMessage
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    // Note: NOT setting errorMessage - this is a success state
                } else {
                    // Update summary with absolute value (expenses are stored negative)
                    let spentAmount = abs(amount)
                    summary.totalSpent += spentAmount
                    if category == "Grocery" {
                        summary.grocerySpent += spentAmount
                    } else if category == "Restaurant" {
                        summary.eatingOutSpent += spentAmount
                    }
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Refresh in background, don't block success
                Task { loadFinanceSummary() }

                isLoading = false
                return true
            } else {
                errorMessage = response.message ?? "Failed to add transaction"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    func updateTransaction(id: Int, merchantName: String, amount: Double, category: String, notes: String?, date: Date) async {
        isLoading = true
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

        isLoading = false
    }

    func deleteTransaction(id: Int) async {
        isLoading = true
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

        isLoading = false
    }

    // MARK: - Income Tracking

    /// Adds income. Returns true on success (including offline queue).
    /// Income amounts are always stored as positive values.
    @discardableResult
    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async -> Bool {
        isLoading = true
        errorMessage = nil

        // Income is always positive
        let incomeAmount = abs(amount)

        do {
            let response = try await api.addIncomeOffline(
                source: source,
                amount: incomeAmount,
                category: category
            )

            if response.success {
                // Queued offline is still a success
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    // Note: NOT setting errorMessage - this is a success state
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Refresh in background, don't block success
                Task { loadFinanceSummary() }

                isLoading = false
                return true
            } else {
                errorMessage = response.message ?? "Failed to add income"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
            return false
        }
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
        isLoading = true
        errorMessage = nil

        let request = CreateCorrectionRequest(
            transactionId: transactionId,
            amount: amount,
            currency: nil,
            category: category,
            merchantName: merchantName,
            date: date.map { ISO8601DateFormatter().string(from: $0) },
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
                isLoading = false
                return true
            } else {
                errorMessage = response.message ?? "Failed to create correction"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    func deactivateCorrection(correctionId: Int) async {
        isLoading = true
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

        isLoading = false
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
