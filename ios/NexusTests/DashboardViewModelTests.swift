import XCTest
@testable import Nexus

/// Tests for DashboardViewModel
@MainActor
final class DashboardViewModelTests: XCTestCase {

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        let vm = DashboardViewModel()

        XCTAssertNil(vm.errorMessage, "Error message should be nil initially")
        XCTAssertNil(vm.lastSyncDate, "Last sync date should be nil initially")
        XCTAssertEqual(vm.recentLogs.count, 0, "Recent logs should be empty initially")
    }

    // MARK: - DailySummary Tests

    func testDailySummaryDefaults() {
        let summary = DailySummary()

        XCTAssertEqual(summary.calories, 0)
        XCTAssertEqual(summary.protein, 0)
        XCTAssertEqual(summary.water, 0)
        XCTAssertNil(summary.weight)
        XCTAssertNil(summary.mood)
        XCTAssertNil(summary.energy)
    }

    // MARK: - Error State Tests

    func testErrorMessageCanBeSet() {
        let vm = DashboardViewModel()
        vm.errorMessage = "Test error"

        XCTAssertEqual(vm.errorMessage, "Test error")
    }

    func testErrorMessageCanBeCleared() {
        let vm = DashboardViewModel()
        vm.errorMessage = "Test error"
        vm.errorMessage = nil

        XCTAssertNil(vm.errorMessage)
    }
}
