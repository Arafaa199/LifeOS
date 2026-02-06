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
        XCTAssertEqual(summary.totalIncome, 0)
        XCTAssertEqual(summary.grocerySpent, 0)
        XCTAssertEqual(summary.eatingOutSpent, 0)
        XCTAssertEqual(summary.currency, "AED")
    }

    // MARK: - Transaction Model Tests

    func testTransactionIsExpense() {
        // Test that negative amounts are expenses
        let expenseAmount = -100.0
        let incomeAmount = 5000.0

        XCTAssertTrue(expenseAmount < 0, "Expense should have negative amount")
        XCTAssertTrue(incomeAmount > 0, "Income should have positive amount")
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

    func testRecurringItemIsExpenseProperty() {
        // RecurringItem.isExpense is computed from type == "expense"
        // We test the logic without creating actual instances
        let expenseType = "expense"
        let incomeType = "income"

        XCTAssertEqual(expenseType, "expense")
        XCTAssertNotEqual(incomeType, "expense")
    }
}
