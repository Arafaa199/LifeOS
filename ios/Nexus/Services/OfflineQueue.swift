import Foundation
import Combine
import os

// Offline queue manager for handling failed API requests
class OfflineQueue {
    static let shared = OfflineQueue()

    private let queueKey = "offline_log_queue"
    private let maxRetries = 5
    private let baseRetryDelay: TimeInterval = 5.0 // Base delay for exponential backoff
    private let maxRetryDelay: TimeInterval = 60.0 // Cap at 60 seconds
    private var processingTask: Task<Void, Never>?
    private let isProcessing = OSAllocatedUnfairLock(initialState: false)
    private var networkCancellable: AnyCancellable?

    struct QueuedEntry: Codable {
        let id: UUID
        let type: String // "food", "water", "universal", etc
        let payload: String // JSON string of the request
        let timestamp: Date
        var retryCount: Int
        let originalRequest: QueuedRequest

        enum QueuedRequest: Codable {
            case food(text: String)
            case water(amount: Int)
            case weight(kg: Double)
            case mood(value: Int, energy: Int?)
            case universal(text: String)
            // Finance operations
            case expense(text: String, clientId: String)
            case transaction(merchant: String, amount: Double, category: String?, clientId: String)
            case income(source: String, amount: Double, category: String, clientId: String)

            var endpoint: String {
                switch self {
                case .food: return "/webhook/nexus-food"
                case .water: return "/webhook/nexus-water"
                case .weight: return "/webhook/nexus-weight"
                case .mood: return "/webhook/nexus-mood"
                case .universal: return "/webhook/nexus-universal"
                case .expense: return "/webhook/nexus-expense"
                case .transaction: return "/webhook/nexus-transaction"
                case .income: return "/webhook/nexus-income"
                }
            }
        }
    }

    private init() {
        // Process queue on init if items exist
        scheduleProcessing()

        // Observe network changes - process queue when network becomes available
        observeNetworkChanges()
    }

    private func observeNetworkChanges() {
        // Subscribe to network connectivity changes
        networkCancellable = NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                let busy = self.isProcessing.withLock { $0 }
                if isConnected && !busy {
                    // Network became available - try to process queue
                    self.scheduleProcessing()
                }
            }
    }

    /// Calculate retry delay with exponential backoff
    /// 5s -> 10s -> 20s -> 40s -> 60s (capped)
    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let delay = baseRetryDelay * pow(2.0, Double(attempt))
        return min(delay, maxRetryDelay)
    }

    private func scheduleProcessing() {
        let busy = isProcessing.withLock { $0 }
        guard processingTask == nil, !busy else { return }
        processingTask = Task {
            await processQueue()
            processingTask = nil
        }
    }

    // MARK: - Add to Queue

    func enqueue(_ request: QueuedEntry.QueuedRequest) {
        var queue = loadQueue()

        let entry = QueuedEntry(
            id: UUID(),
            type: describeRequest(request),
            payload: "",
            timestamp: Date(),
            retryCount: 0,
            originalRequest: request
        )

        queue.append(entry)
        saveQueue(queue)

        // Schedule processing (won't start if already running)
        scheduleProcessing()
    }

    // MARK: - Process Queue

    func processQueue() async {
        let alreadyRunning = isProcessing.withLock { value -> Bool in
            if value { return true }
            value = true
            return false
        }
        guard !alreadyRunning else { return }
        defer { isProcessing.withLock { $0 = false } }

        var queue = loadQueue()
        guard !queue.isEmpty else { return }

        var processed: [UUID] = []
        var failed: [QueuedEntry] = []

        for var entry in queue {
            // Check for cancellation
            if Task.isCancelled { break }

            do {
                // Try to send the request
                try await sendRequest(entry.originalRequest)

                // Success - mark for removal
                processed.append(entry.id)

            } catch {
                // Failed - increment retry count
                entry.retryCount += 1

                if entry.retryCount >= maxRetries {
                    // Max retries reached - remove from queue
                    processed.append(entry.id)
                    #if DEBUG
                    print("❌ Offline queue: Max retries reached for \(entry.type)")
                    #endif
                } else {
                    // Keep in queue for retry
                    failed.append(entry)
                }
            }
        }

        // Remove processed entries
        queue.removeAll { processed.contains($0.id) }

        // Update failed entries with new retry count
        for failedEntry in failed {
            if let index = queue.firstIndex(where: { $0.id == failedEntry.id }) {
                queue[index] = failedEntry
            }
        }

        saveQueue(queue)

        // If items remain, schedule retry after delay with exponential backoff
        if !queue.isEmpty && !Task.isCancelled {
            // Use the max retry count from remaining items to determine delay
            let maxAttempt = queue.map(\.retryCount).max() ?? 0
            let delay = retryDelay(forAttempt: maxAttempt)

            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled {
                    scheduleProcessing()
                }
            }
        }
    }

    private func sendRequest(_ request: QueuedEntry.QueuedRequest) async throws {
        let api = NexusAPI.shared

        switch request {
        case .food(let text):
            _ = try await api.logFood(text)
        case .water(let amount):
            _ = try await api.logWater(amountML: amount)
        case .weight(let kg):
            _ = try await api.logWeight(kg: kg)
        case .mood(let value, let energy):
            _ = try await api.logMood(mood: value, energy: energy ?? 5)
        case .universal(let text):
            _ = try await api.logUniversal(text)
        case .expense(let text, let clientId):
            _ = try await api.logExpenseWithClientId(text, clientId: clientId)
        case .transaction(let merchant, let amount, let category, let clientId):
            _ = try await api.addTransactionWithClientId(merchant: merchant, amount: amount, category: category, clientId: clientId)
        case .income(let source, let amount, let category, let clientId):
            _ = try await api.addIncomeWithClientId(source: source, amount: amount, category: category, clientId: clientId)
        }
    }

    // MARK: - Persistence

    private func loadQueue() -> [QueuedEntry] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([QueuedEntry].self, from: data) else {
            return []
        }
        return queue
    }

    private func saveQueue(_ queue: [QueuedEntry]) {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    // MARK: - Utilities

    func getQueueCount() -> Int {
        return loadQueue().count
    }

    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    private func describeRequest(_ request: QueuedEntry.QueuedRequest) -> String {
        switch request {
        case .food(let text): return "Food: \(text)"
        case .water(let amount): return "Water: \(amount)ml"
        case .weight(let kg): return "Weight: \(kg)kg"
        case .mood(let value, _): return "Mood: \(value)"
        case .universal(let text): return "Log: \(text)"
        case .expense(let text, _): return "Expense: \(text)"
        case .transaction(let merchant, let amount, _, _): return "Transaction: \(merchant) \(amount)"
        case .income(let source, let amount, _, _): return "Income: \(source) \(amount)"
        }
    }
}

// MARK: - Enhanced NexusAPI with Offline Support

extension NexusAPI {
    func logWithOfflineSupport<T: Encodable>(
        _ endpoint: String,
        body: T,
        queueRequest: OfflineQueue.QueuedEntry.QueuedRequest
    ) async throws -> NexusResponse {
        do {
            // Try to send normally
            return try await post(endpoint, body: body)
        } catch {
            // Failed - add to offline queue
            OfflineQueue.shared.enqueue(queueRequest)

            // Return a mock success response so UI doesn't fail
            return NexusResponse(
                success: true,
                message: "Queued offline - will sync when connected",
                data: nil
            )
        }
    }

    func logFoodOffline(_ text: String) async throws -> NexusResponse {
        let request = FoodLogRequest(text: text)
        return try await logWithOfflineSupport(
            "/webhook/nexus-food",
            body: request,
            queueRequest: .food(text: text)
        )
    }

    func logWaterOffline(_ amount: Int) async throws -> NexusResponse {
        let request = WaterLogRequest(amount_ml: amount)
        return try await logWithOfflineSupport(
            "/webhook/nexus-water",
            body: request,
            queueRequest: .water(amount: amount)
        )
    }

    func logUniversalOffline(_ text: String) async throws -> NexusResponse {
        let request = UniversalLogRequest(text: text)
        return try await logWithOfflineSupport(
            "/webhook/nexus-universal",
            body: request,
            queueRequest: .universal(text: text)
        )
    }

    // MARK: - Finance Offline Support

    func logExpenseOffline(_ text: String) async throws -> FinanceResponse {
        let clientId = UUID().uuidString
        do {
            return try await logExpenseWithClientId(text, clientId: clientId)
        } catch {
            OfflineQueue.shared.enqueue(.expense(text: text, clientId: clientId))
            return FinanceResponse(
                success: true,
                message: "Queued offline - will sync when connected",
                data: nil
            )
        }
    }

    func addTransactionOffline(merchant: String, amount: Double, category: String?) async throws -> FinanceResponse {
        let clientId = UUID().uuidString
        do {
            return try await addTransactionWithClientId(merchant: merchant, amount: amount, category: category, clientId: clientId)
        } catch {
            OfflineQueue.shared.enqueue(.transaction(merchant: merchant, amount: amount, category: category, clientId: clientId))
            return FinanceResponse(
                success: true,
                message: "Queued offline - will sync when connected",
                data: nil
            )
        }
    }

    func addIncomeOffline(source: String, amount: Double, category: String) async throws -> FinanceResponse {
        let clientId = UUID().uuidString
        do {
            return try await addIncomeWithClientId(source: source, amount: amount, category: category, clientId: clientId)
        } catch {
            OfflineQueue.shared.enqueue(.income(source: source, amount: amount, category: category, clientId: clientId))
            return FinanceResponse(
                success: true,
                message: "Queued offline - will sync when connected",
                data: nil
            )
        }
    }
}
