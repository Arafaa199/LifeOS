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

    private let api = NexusAPI.shared
    private let cache = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var loadTask: Task<Void, Never>?

    init() {
        loadFromCache()
        loadFinanceSummary()
        updateQueuedCount()
    }

    func updateQueuedCount() {
        queuedCount = OfflineQueue.shared.getQueueCount()
    }

    deinit {
        loadTask?.cancel()
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
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            // Check network connectivity
            guard networkMonitor.isConnected else {
                isOffline = true
                isLoading = false
                errorMessage = "No internet connection. Showing cached data."
                return
            }

            isOffline = false

            do {
                let response = try await api.fetchFinanceSummary()

                if response.success, let data = response.data {
                    // Update summary with real data from database
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

                    // Cache the data
                    cache.saveFinanceSummary(summary, transactions: recentTransactions)
                    if !summary.budgets.isEmpty {
                        cache.saveBudgets(summary.budgets)
                    }

                    errorMessage = nil
                }
                isLoading = false
            } catch {
                // Use cached data on error
                isOffline = true
                isLoading = false
                errorMessage = "Could not fetch latest data. Showing cached data."
                print("Finance summary fetch failed: \(error)")
            }
        }
    }

    func logExpense(_ text: String) async {
        guard !text.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.logExpenseOffline(text)

            if response.success {
                // Check if queued offline
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    errorMessage = "Queued - will sync when online"
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
                            summary.grocerySpent += normalizedTransaction.amount
                        }
                        if normalizedTransaction.isRestaurant {
                            summary.eatingOutSpent += normalizedTransaction.amount
                        }
                    }
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                loadFinanceSummary()
            } else {
                errorMessage = response.message ?? "Failed to log expense"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refresh() async {
        await loadFinanceSummary()
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

    func addManualTransaction(merchantName: String, amount: Double, category: String, notes: String?, date: Date) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.addTransactionOffline(
                merchant: merchantName,
                amount: amount,
                category: category
            )

            if response.success {
                // Check if queued offline
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    errorMessage = "Queued - will sync when online"
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

                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to add transaction"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
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

    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.addIncomeOffline(
                source: source,
                amount: amount,
                category: category
            )

            if response.success {
                if response.message?.contains("Queued offline") == true {
                    updateQueuedCount()
                    errorMessage = "Queued - will sync when online"
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                await refresh()
            } else {
                errorMessage = response.message ?? "Failed to add income"
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
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
