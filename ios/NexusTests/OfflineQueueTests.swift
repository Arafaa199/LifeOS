import XCTest
@testable import Nexus

/// Tests for OfflineQueue (Patch 2: Queue behavior and persistence)
@MainActor
final class OfflineQueueTests: XCTestCase {

    // MARK: - Queue Entry Tests

    func testQueuedEntryPreservesClientId() {
        // Transaction requests include clientId for idempotency
        let clientId = UUID().uuidString
        let request = OfflineQueue.QueuedEntry.QueuedRequest.transaction(
            merchant: "Test Store",
            amount: 50.0,
            category: "Shopping",
            clientId: clientId
        )

        // Verify clientId is preserved in the request
        if case .transaction(_, _, _, let storedClientId) = request {
            XCTAssertEqual(storedClientId, clientId, "clientId should be preserved in transaction request")
        } else {
            XCTFail("Request should be a transaction")
        }
    }

    func testQueuedEntryPreservesExpenseClientId() {
        let clientId = UUID().uuidString
        let request = OfflineQueue.QueuedEntry.QueuedRequest.expense(
            text: "Coffee",
            clientId: clientId
        )

        if case .expense(let text, let storedClientId) = request {
            XCTAssertEqual(storedClientId, clientId, "clientId should be preserved in expense request")
            XCTAssertEqual(text, "Coffee")
        } else {
            XCTFail("Request should be an expense")
        }
    }

    func testQueuedEntryPreservesIncomeClientId() {
        let clientId = UUID().uuidString
        let request = OfflineQueue.QueuedEntry.QueuedRequest.income(
            source: "Salary",
            amount: 5000.0,
            category: "Income",
            clientId: clientId
        )

        if case .income(_, _, _, let storedClientId) = request {
            XCTAssertEqual(storedClientId, clientId, "clientId should be preserved in income request")
        } else {
            XCTFail("Request should be an income")
        }
    }

    // MARK: - Endpoint Mapping Tests

    func testRequestEndpointMapping() {
        let testCases: [(OfflineQueue.QueuedEntry.QueuedRequest, String)] = [
            (.food(text: "eggs"), "/webhook/nexus-food-log"),
            (.water(amount: 500), "/webhook/nexus-water"),
            (.weight(kg: 75.0), "/webhook/nexus-weight"),
            (.mood(value: 7, energy: 8), "/webhook/nexus-mood"),
            (.universal(text: "test"), "/webhook/nexus-universal"),
            (.expense(text: "coffee", clientId: "abc"), "/webhook/nexus-expense"),
            (.transaction(merchant: "Store", amount: 10.0, category: nil, clientId: "xyz"), "/webhook/nexus-transaction"),
            (.income(source: "Salary", amount: 5000.0, category: "Income", clientId: "123"), "/webhook/nexus-income"),
        ]

        for (request, expectedEndpoint) in testCases {
            XCTAssertEqual(request.endpoint, expectedEndpoint, "Endpoint mismatch for \(request)")
        }
    }

    // MARK: - Priority Tests

    func testPriorityOrdering() {
        XCTAssertLessThan(
            OfflineQueue.QueuedEntry.Priority.high.rawValue,
            OfflineQueue.QueuedEntry.Priority.normal.rawValue,
            "High priority should have lower raw value"
        )
        XCTAssertLessThan(
            OfflineQueue.QueuedEntry.Priority.normal.rawValue,
            OfflineQueue.QueuedEntry.Priority.low.rawValue,
            "Normal priority should have lower raw value than low"
        )
    }

    // MARK: - Queue Entry Codable Tests

    func testQueuedEntryEncodeDecode() throws {
        let entry = OfflineQueue.QueuedEntry(
            id: UUID(),
            type: "food",
            payload: "",
            timestamp: Date(),
            retryCount: 2,
            priority: .high,
            originalRequest: .food(text: "chicken breast")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OfflineQueue.QueuedEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.type, entry.type)
        XCTAssertEqual(decoded.retryCount, entry.retryCount)
        XCTAssertEqual(decoded.priority, entry.priority)

        if case .food(let text) = decoded.originalRequest {
            XCTAssertEqual(text, "chicken breast")
        } else {
            XCTFail("Decoded request should be food")
        }
    }

    func testTransactionRequestEncodeDecode() throws {
        let clientId = UUID().uuidString
        let request = OfflineQueue.QueuedEntry.QueuedRequest.transaction(
            merchant: "Amazon",
            amount: 99.99,
            category: "Shopping",
            clientId: clientId
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OfflineQueue.QueuedEntry.QueuedRequest.self, from: data)

        if case .transaction(let merchant, let amount, let category, let decodedClientId) = decoded {
            XCTAssertEqual(merchant, "Amazon")
            XCTAssertEqual(amount, 99.99, accuracy: 0.01)
            XCTAssertEqual(category, "Shopping")
            XCTAssertEqual(decodedClientId, clientId, "clientId should survive encode/decode cycle")
        } else {
            XCTFail("Decoded request should be transaction")
        }
    }

    // MARK: - OfflineOperationResult Tests

    func testOperationResultSucceeded() {
        XCTAssertTrue(OfflineOperationResult.success.succeeded)
        XCTAssertFalse(OfflineOperationResult.queued(count: 5).succeeded)
        XCTAssertFalse(OfflineOperationResult.failed(APIError.offline).succeeded)
    }

    func testOperationResultWasQueued() {
        XCTAssertFalse(OfflineOperationResult.success.wasQueued)
        XCTAssertTrue(OfflineOperationResult.queued(count: 5).wasQueued)
        XCTAssertFalse(OfflineOperationResult.failed(APIError.offline).wasQueued)
    }

    func testQueuedCountAccessible() {
        let result = OfflineOperationResult.queued(count: 7)
        if case .queued(let count) = result {
            XCTAssertEqual(count, 7)
        } else {
            XCTFail("Should be queued result")
        }
    }
}
