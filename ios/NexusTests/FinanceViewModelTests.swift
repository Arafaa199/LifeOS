import XCTest
@testable import Nexus

/// Tests for FinanceViewModel
@MainActor
final class FinanceViewModelTests: XCTestCase {

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        let vm = FinanceViewModel()

        XCTAssertNil(vm.errorMessage, "Error message should be nil initially")
        XCTAssertNil(vm.pendingMessage, "Pending message should be nil initially")
        XCTAssertEqual(vm.recentTransactions.count, 0, "Recent transactions should be empty initially")
        XCTAssertEqual(vm.recurringItems.count, 0, "Recurring items should be empty initially")
    }

    // MARK: - FinanceSummary Tests

    func testFinanceSummaryDefaults() {
        let summary = FinanceSummary()

        XCTAssertEqual(summary.totalSpent, 0)
        XCTAssertEqual(summary.budgetRemaining, 0)
        XCTAssertEqual(summary.transactionCount, 0)
    }

    // MARK: - Transaction Model Tests

    func testTransactionInitialization() {
        let transaction = Transaction(
            id: 1,
            merchantName: "Starbucks",
            amount: -5.50,
            category: "Food",
            date: Date(),
            notes: nil
        )

        XCTAssertEqual(transaction.id, 1)
        XCTAssertEqual(transaction.merchantName, "Starbucks")
        XCTAssertEqual(transaction.amount, -5.50, accuracy: 0.01)
        XCTAssertEqual(transaction.category, "Food")
        XCTAssertNil(transaction.notes)
    }

    func testTransactionIsExpense() {
        let expense = Transaction(
            id: 1,
            merchantName: "Store",
            amount: -100.0,
            category: "Shopping",
            date: Date(),
            notes: nil
        )

        let income = Transaction(
            id: 2,
            merchantName: "Salary",
            amount: 5000.0,
            category: "Income",
            date: Date(),
            notes: nil
        )

        XCTAssertTrue(expense.amount < 0, "Expense should have negative amount")
        XCTAssertTrue(income.amount > 0, "Income should have positive amount")
    }

    // MARK: - Error State Tests

    func testErrorMessageCanBeSet() {
        let vm = FinanceViewModel()
        vm.errorMessage = "Failed to load"

        XCTAssertEqual(vm.errorMessage, "Failed to load")
    }

    func testPendingMessageCanBeSet() {
        let vm = FinanceViewModel()
        vm.pendingMessage = "Transaction queued"

        XCTAssertEqual(vm.pendingMessage, "Transaction queued")
    }

    // MARK: - RecurringItem Tests

    func testRecurringItemInitialization() {
        let item = RecurringItem(
            id: 1,
            merchantName: "Netflix",
            amount: 15.99,
            frequency: "monthly",
            nextDueDate: Date(),
            category: "Entertainment"
        )

        XCTAssertEqual(item.merchantName, "Netflix")
        XCTAssertEqual(item.amount, 15.99, accuracy: 0.01)
        XCTAssertEqual(item.frequency, "monthly")
        XCTAssertEqual(item.category, "Entertainment")
    }
}
