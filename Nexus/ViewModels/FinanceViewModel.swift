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

    private let api = NexusAPI.shared
    private let cache = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var loadTask: Task<Void, Never>?

    init() {
        loadFromCache()
        loadFinanceSummary()
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
        loadTask = Task {
            guard !Task.isCancelled else { return }

            // Check network connectivity
            guard networkMonitor.isConnected else {
                isOffline = true
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
                        recentTransactions = transactions
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
            } catch {
                // Use cached data on error
                isOffline = true
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
            let response = try await api.logExpense(text)

            if response.success {
                // Update summary with response data
                if let data = response.data {
                    if let totalSpent = data.totalSpent {
                        summary.totalSpent = totalSpent
                    }
                    if let categorySpent = data.categorySpent {
                        // Update category breakdown
                    }
                    if let transaction = data.transaction {
                        recentTransactions.insert(transaction, at: 0)
                        if recentTransactions.count > 20 {
                            recentTransactions = Array(recentTransactions.prefix(20))
                        }

                        // Update category totals
                        if transaction.isGrocery {
                            summary.grocerySpent += transaction.amount
                        }
                        if transaction.isRestaurant {
                            summary.eatingOutSpent += transaction.amount
                        }
                    }
                }

                // Success feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
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
            let response = try await api.addTransaction(
                merchantName,
                amount: amount,
                category: category,
                notes: notes
            )

            if response.success {
                // Success feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Update local summary
                summary.totalSpent += amount
                if category == "Grocery" {
                    summary.grocerySpent += amount
                } else if category == "Restaurant" {
                    summary.eatingOutSpent += amount
                }

                // Reload transactions
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
            let response = try await api.addIncome(
                source: source,
                amount: amount,
                category: category,
                notes: notes,
                date: date,
                isRecurring: isRecurring
            )

            if response.success {
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
