import Foundation

// MARK: - API Client Protocol

/// Protocol defining the API client interface for dependency injection and testing
protocol APIClientProtocol: Sendable {
    // Health logging
    func logFood(_ text: String, foodId: Int?, mealType: String?) async throws -> NexusResponse
    func logWeight(kg: Double) async throws -> NexusResponse
    func logMood(mood: Int, energy: Int, notes: String?) async throws -> NexusResponse
    func logUniversal(_ text: String) async throws -> NexusResponse
    
    // Offline support (returns result tuple with classification)
    func logFoodOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult)
    func logUniversalOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult)
    
    // Finance
    func logExpense(_ text: String) async throws -> FinanceResponse
    func addTransaction(_ merchantName: String, amount: Double, category: String?, notes: String?) async throws -> FinanceResponse
    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async throws -> FinanceResponse
    
    // Data fetching
    func fetchDailySummary(for date: Date) async throws -> DailySummaryResponse
    func fetchFinanceSummary() async throws -> FinanceResponse
    func fetchSyncStatus() async throws -> SyncStatusResponse
}

// Make NexusAPI conform to the protocol
extension NexusAPI: APIClientProtocol {}

// MARK: - Mock API Client

/// Mock API client for testing and previews
actor MockAPIClient: APIClientProtocol {
    var shouldSucceed = true
    var mockDelay: TimeInterval = 0.5
    
    func logFood(_ text: String, foodId: Int?, mealType: String?) async throws -> NexusResponse {
        try await simulateRequest()
        return NexusResponse(
            success: shouldSucceed,
            message: "Food logged: \(text)",
            data: ResponseData(calories: 250, protein: 20, total_water_ml: nil, weight_kg: nil)
        )
    }
    
    func logWeight(kg: Double) async throws -> NexusResponse {
        try await simulateRequest()
        return NexusResponse(
            success: shouldSucceed,
            message: "Weight logged",
            data: ResponseData(calories: nil, protein: nil, total_water_ml: nil, weight_kg: kg)
        )
    }
    
    func logMood(mood: Int, energy: Int, notes: String?) async throws -> NexusResponse {
        try await simulateRequest()
        return NexusResponse(
            success: shouldSucceed,
            message: "Mood logged",
            data: nil
        )
    }
    
    func logUniversal(_ text: String) async throws -> NexusResponse {
        try await simulateRequest()
        return NexusResponse(
            success: shouldSucceed,
            message: "Universal log: \(text)",
            data: nil
        )
    }
    
    func logFoodOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        do {
            let response = try await logFood(text, foodId: nil, mealType: nil)
            return (response, .success)
        } catch {
            return (nil, .failed(error))
        }
    }

    func logUniversalOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        do {
            let response = try await logUniversal(text)
            return (response, .success)
        } catch {
            return (nil, .failed(error))
        }
    }
    
    func logExpense(_ text: String) async throws -> FinanceResponse {
        try await simulateRequest()
        return FinanceResponse(
            success: shouldSucceed,
            message: "Expense logged: \(text)",
            data: nil
        )
    }
    
    func addTransaction(_ merchantName: String, amount: Double, category: String?, notes: String?) async throws -> FinanceResponse {
        try await simulateRequest()
        return FinanceResponse(
            success: shouldSucceed,
            message: "Transaction added",
            data: nil
        )
    }
    
    func addIncome(source: String, amount: Double, category: String, notes: String?, date: Date, isRecurring: Bool) async throws -> FinanceResponse {
        try await simulateRequest()
        return FinanceResponse(
            success: shouldSucceed,
            message: "Income added",
            data: nil
        )
    }
    
    func fetchDailySummary(for date: Date) async throws -> DailySummaryResponse {
        try await simulateRequest()
        let data = DailySummaryData(
            date: ISO8601DateFormatter().string(from: date),
            calories: 1850,
            protein: 95.5,
            water: 2000,
            weight: 75.0,
            mood: 7,
            energy: 8,
            logs: []
        )
        return DailySummaryResponse(success: true, data: data)
    }
    
    func fetchFinanceSummary() async throws -> FinanceResponse {
        try await simulateRequest()
        return FinanceResponse(
            success: shouldSucceed,
            message: "Finance summary fetched",
            data: nil
        )
    }
    
    func fetchSyncStatus() async throws -> SyncStatusResponse {
        try await simulateRequest()
        let domain = SyncDomainStatus(
            domain: "health",
            last_success_at: ISO8601DateFormatter().string(from: Date()),
            last_success_rows: 10,
            last_success_duration_ms: 150,
            last_success_source: "ios",
            last_error_at: nil,
            last_error: nil,
            running_count: 0,
            freshness: "current",
            seconds_since_success: 30
        )
        return SyncStatusResponse(
            success: true,
            domains: [domain],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // MARK: - Helpers
    
    private func simulateRequest() async throws {
        try await Task.sleep(nanoseconds: UInt64(mockDelay * 1_000_000_000))
        if !shouldSucceed {
            throw APIError.serverError(500)
        }
    }
}

// MARK: - Environment Key for Dependency Injection

import SwiftUI

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClientProtocol = NexusAPI.shared
}

extension EnvironmentValues {
    var apiClient: APIClientProtocol {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

// MARK: - Usage Examples in Views

/*
 // In your view:
 struct MyView: View {
     @Environment(\.apiClient) var api
     
     var body: some View {
         Button("Log Food") {
             Task {
                 try await api.logFood("chicken")
             }
         }
     }
 }
 
 // For previews with mock data:
 #Preview {
     MyView()
         .environment(\.apiClient, MockAPIClient())
 }
 
 // For testing:
 let mockAPI = MockAPIClient()
 await mockAPI.setShouldSucceed(false)
 // Test error handling
 */
