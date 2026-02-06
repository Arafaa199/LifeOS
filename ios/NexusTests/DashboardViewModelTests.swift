import XCTest
@testable import Nexus

/// Tests for DashboardViewModel and related models
@MainActor
final class DashboardViewModelTests: XCTestCase {

    // MARK: - DailySummary Tests

    func testDailySummaryDefaults() {
        let summary = DailySummary()

        XCTAssertEqual(summary.totalCalories, 0)
        XCTAssertEqual(summary.totalProtein, 0)
        XCTAssertEqual(summary.totalWater, 0)
        XCTAssertNil(summary.latestWeight)
        XCTAssertNil(summary.mood)
        XCTAssertNil(summary.energy)
    }

    func testDailySummaryWeightBackwardCompatibility() {
        var summary = DailySummary()
        summary.latestWeight = 75.5

        // weight property should mirror latestWeight
        XCTAssertEqual(summary.weight, 75.5)
    }

}
