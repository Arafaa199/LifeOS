import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "offline")

// MARK: - Error Classification

/// Classifies errors to determine if they should be queued for retry
enum ErrorClassification: CustomStringConvertible {
    case transient      // Network errors, timeouts, 5xx - should retry
    case clientError    // 4xx errors - user/validation issue, don't retry
    case authError      // 401/403 - auth issue, surface to UI
    case permanent      // Decoding, invalid URL - won't succeed on retry

    var description: String {
        switch self {
        case .transient: return "transient"
        case .clientError: return "clientError"
        case .authError: return "authError"
        case .permanent: return "permanent"
        }
    }

    /// Classify any error for queue decision
    static func classify(_ error: Error) -> ErrorClassification {
        // URLError cases
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .transient
            case .userAuthenticationRequired:
                return .authError
            default:
                return .transient
            }
        }

        // APIError cases
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code):
                if code == 401 || code == 403 {
                    return .authError
                } else if code >= 400 && code < 500 {
                    return .clientError
                } else if code >= 500 {
                    return .transient
                }
                return .permanent
            case .offline:
                return .transient
            case .invalidURL, .invalidResponse, .decodingError:
                return .permanent
            }
        }

        // NexusError cases
        if let nexusError = error as? NexusError {
            switch nexusError {
            case .network:
                return .transient
            case .offline:
                return .transient
            case .validation:
                return .clientError
            case .api(let apiError):
                return classify(apiError)
            case .unknown(let underlying):
                return classify(underlying)
            }
        }

        // ValidationError - never retry
        if error is ValidationError {
            return .clientError
        }

        // Default to transient for unknown errors (safer to retry)
        return .transient
    }

    var shouldQueue: Bool {
        self == .transient
    }

    var userMessage: String {
        switch self {
        case .transient:
            return "Request queued for retry when online"
        case .clientError:
            return "Invalid request - please check your input"
        case .authError:
            return "Authentication failed - check your API key in Settings"
        case .permanent:
            return "Request failed - please try again"
        }
    }
}

// MARK: - Operation Result

/// Result of an offline-supported operation
enum OfflineOperationResult {
    case success                    // Request succeeded immediately
    case queued(count: Int)         // Queued for later (returns queue count)
    case failed(Error)              // Failed and NOT queued (client/auth/permanent error)

    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }

    var wasQueued: Bool {
        if case .queued = self { return true }
        return false
    }
}

// Offline queue manager for handling failed API requests
@MainActor
class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    private let queueKey = "offline_log_queue"
    private let failedKey = "offline_failed_items"
    private let maxRetries = 5
    private let maxQueueSize = 1000
    private let baseRetryDelay: TimeInterval = 5.0
    private let maxRetryDelay: TimeInterval = 60.0
    private var processingTask: Task<Void, Never>?
    private var isProcessing = false
    private var networkCancellable: AnyCancellable?

    // MARK: - Published State for UI
    @Published private(set) var failedItemCount: Int = 0
    @Published private(set) var pendingItemCount: Int = 0

    // MARK: - Failed Item Storage
    struct FailedEntry: Codable, Identifiable {
        let id: UUID
        let type: String
        let description: String
        let timestamp: Date
        let failedAt: Date
        let lastError: String
        let originalRequest: QueuedEntry.QueuedRequest
    }

    struct QueuedEntry: Codable, Sendable {
        let id: UUID
        let type: String
        let payload: String
        let timestamp: Date
        var retryCount: Int
        let priority: Priority
        let originalRequest: QueuedRequest

        enum Priority: Int, Codable, Sendable {
            case high = 0
            case normal = 1
            case low = 2
        }

        enum QueuedRequest: Codable, Sendable {
            case food(text: String)
            case water(amount: Int)
            case weight(kg: Double)
            case mood(value: Int, energy: Int?)
            case universal(text: String)
            case expense(text: String, clientId: String)
            case transaction(merchant: String, amount: Double, category: String?, clientId: String)
            case income(source: String, amount: Double, category: String, clientId: String)

            var endpoint: String {
                switch self {
                case .food: return "/webhook/nexus-food-log"
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
        updateCounts()
        Task { scheduleProcessing() }
        observeNetworkChanges()
    }

    private func updateCounts() {
        pendingItemCount = loadQueue().count
        failedItemCount = loadFailedItems().count
    }

    private func observeNetworkChanges() {
        networkCancellable = NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self else { return }
                if isConnected && !self.isProcessing {
                    self.scheduleProcessing()
                }
            }
    }

    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let delay = baseRetryDelay * pow(2.0, Double(attempt))
        return min(delay, maxRetryDelay)
    }

    private func scheduleProcessing() {
        guard processingTask == nil, !isProcessing else { return }
        processingTask = Task {
            await processQueue()
            processingTask = nil
        }
    }

    // MARK: - Add to Queue

    func enqueue(_ request: QueuedEntry.QueuedRequest, priority: QueuedEntry.Priority = .normal) {
        var queue = loadQueue()

        if queue.count >= self.maxQueueSize {
            logger.warning("Queue at capacity, removing \(queue.count - self.maxQueueSize + 1) oldest items")
            queue.removeFirst(queue.count - self.maxQueueSize + 1)
        }

        let entry = QueuedEntry(
            id: UUID(),
            type: describeRequest(request),
            payload: "",
            timestamp: Date(),
            retryCount: 0,
            priority: priority,
            originalRequest: request
        )

        queue.append(entry)
        saveQueue(queue)

        logger.info("Enqueued \(entry.type) with priority \(priority.rawValue)")

        scheduleProcessing()
    }

    // MARK: - Process Queue

    func processQueue() async {
        guard !isProcessing else {
            logger.debug("Queue processing already in progress")
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
            updateCounts()
        }

        var queue = loadQueue()
        guard !queue.isEmpty else {
            logger.debug("Queue is empty")
            return
        }

        logger.info("Processing \(queue.count) queued items")

        queue.sort { $0.priority.rawValue < $1.priority.rawValue }

        var processed: [UUID] = []
        var retrying: [QueuedEntry] = []
        var permanentlyFailed: [(entry: QueuedEntry, error: String)] = []

        for var entry in queue {
            if Task.isCancelled { break }

            do {
                try await sendRequest(entry.originalRequest)
                processed.append(entry.id)
                logger.info("Successfully synced: \(entry.type)")

            } catch {
                entry.retryCount += 1

                if entry.retryCount >= self.maxRetries {
                    processed.append(entry.id)
                    permanentlyFailed.append((entry, error.localizedDescription))
                    logger.error("Max retries reached for \(entry.type): \(error.localizedDescription)")
                } else {
                    retrying.append(entry)
                    logger.warning("Retry \(entry.retryCount)/\(self.maxRetries) for \(entry.type): \(error.localizedDescription)")
                }
            }
        }

        // Move permanently failed items to failed storage (NOT deleted!)
        for (entry, errorMsg) in permanentlyFailed {
            moveToFailed(entry, lastError: errorMsg)
        }

        queue.removeAll { processed.contains($0.id) }

        for retryEntry in retrying {
            if let index = queue.firstIndex(where: { $0.id == retryEntry.id }) {
                queue[index] = retryEntry
            }
        }

        saveQueue(queue)

        logger.info("Queue processing complete. Remaining: \(queue.count), Failed: \(permanentlyFailed.count)")

        if !queue.isEmpty && !Task.isCancelled {
            let maxAttempt = queue.map(\.retryCount).max() ?? 0
            let delay = retryDelay(forAttempt: maxAttempt)

            logger.info("Scheduling retry in \(delay)s")

            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled {
                    scheduleProcessing()
                }
            }
        }
    }

    private func moveToFailed(_ entry: QueuedEntry, lastError: String) {
        var failedItems = loadFailedItems()
        let failedEntry = FailedEntry(
            id: entry.id,
            type: entry.type,
            description: describeRequest(entry.originalRequest),
            timestamp: entry.timestamp,
            failedAt: Date(),
            lastError: lastError,
            originalRequest: entry.originalRequest
        )
        failedItems.append(failedEntry)
        saveFailedItems(failedItems)
        logger.warning("Moved to failed items: \(entry.type) - \(lastError)")

        // Post notification for UI to show alert
        NotificationCenter.default.post(
            name: .offlineItemPermanentlyFailed,
            object: nil,
            userInfo: ["description": failedEntry.description, "error": lastError]
        )
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
        do {
            let data = try JSONEncoder().encode(queue)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            logger.error("Failed to encode offline queue (\(queue.count) items): \(error.localizedDescription)")
        }
    }

    // MARK: - Failed Items Persistence

    private func loadFailedItems() -> [FailedEntry] {
        guard let data = UserDefaults.standard.data(forKey: failedKey),
              let items = try? JSONDecoder().decode([FailedEntry].self, from: data) else {
            return []
        }
        return items
    }

    private func saveFailedItems(_ items: [FailedEntry]) {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: failedKey)
        } catch {
            logger.error("Failed to encode failed items (\(items.count)): \(error.localizedDescription)")
        }
    }

    // MARK: - Public Failed Items API

    /// Returns all permanently failed items that need user attention
    func getFailedItems() -> [FailedEntry] {
        return loadFailedItems()
    }

    /// Retry a specific failed item - moves it back to the pending queue
    func retryFailedItem(id: UUID) {
        var failedItems = loadFailedItems()
        guard let index = failedItems.firstIndex(where: { $0.id == id }) else { return }

        let item = failedItems.remove(at: index)
        saveFailedItems(failedItems)

        // Re-enqueue with high priority
        enqueue(item.originalRequest, priority: .high)
        updateCounts()
        logger.info("Retrying failed item: \(item.description)")
    }

    /// Discard a failed item (user acknowledges data loss)
    func discardFailedItem(id: UUID) {
        var failedItems = loadFailedItems()
        failedItems.removeAll { $0.id == id }
        saveFailedItems(failedItems)
        updateCounts()
        logger.info("Discarded failed item: \(id)")
    }

    /// Clear all failed items (user acknowledges data loss)
    func clearFailedItems() {
        UserDefaults.standard.removeObject(forKey: failedKey)
        updateCounts()
    }

    // MARK: - Utilities

    func getQueueCount() -> Int {
        return loadQueue().count
    }

    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
        updateCounts()
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

// MARK: - Notification Names

extension Notification.Name {
    static let offlineItemPermanentlyFailed = Notification.Name("offlineItemPermanentlyFailed")
}

// MARK: - Enhanced NexusAPI with Offline Support

extension NexusAPI {
    /// Performs a request with smart offline support.
    /// Only queues transient errors (network, 5xx). Surfaces 4xx/auth/validation to caller.
    func logWithOfflineSupport<T: Encodable>(
        _ endpoint: String,
        body: T,
        queueRequest: OfflineQueue.QueuedEntry.QueuedRequest,
        priority: OfflineQueue.QueuedEntry.Priority = .normal
    ) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        do {
            let response = try await post(endpoint, body: body)
            return (response, .success)
        } catch {
            let classification = ErrorClassification.classify(error)

            if classification.shouldQueue {
                OfflineQueue.shared.enqueue(queueRequest, priority: priority)
                let count = OfflineQueue.shared.getQueueCount()
                logger.info("Queued request (\(count) total): \(classification.userMessage)")
                // IMPORTANT: success: false - item is NOT confirmed on server yet
                // Callers must check .queued result and handle pending state appropriately
                return (NexusResponse(
                    success: false,
                    message: "Saved locally - will sync when online",
                    data: nil
                ), .queued(count: count))
            } else {
                logger.warning("Not queuing \(endpoint): \(classification) - \(error.localizedDescription)")
                return (nil, .failed(error))
            }
        }
    }

    func logFoodOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        let request = FoodLogRequest(text: text)
        return await logWithOfflineSupport(
            "/webhook/nexus-food-log",
            body: request,
            queueRequest: .food(text: text)
        )
    }

    func logWaterOffline(_ amount: Int) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        guard let request = try? WaterLogRequest(amount_ml: amount) else {
            return (nil, .failed(ValidationError.invalidWaterAmount))
        }
        return await logWithOfflineSupport(
            "/webhook/nexus-water",
            body: request,
            queueRequest: .water(amount: amount)
        )
    }

    func logUniversalOffline(_ text: String) async -> (response: NexusResponse?, result: OfflineOperationResult) {
        let request = UniversalLogRequest(text: text)
        return await logWithOfflineSupport(
            "/webhook/nexus-universal",
            body: request,
            queueRequest: .universal(text: text)
        )
    }

    // MARK: - Finance Offline Support

    func logExpenseOffline(_ text: String) async -> (response: FinanceResponse?, result: OfflineOperationResult) {
        let clientId = UUID().uuidString
        do {
            let response = try await logExpenseWithClientId(text, clientId: clientId)
            return (response, .success)
        } catch {
            let classification = ErrorClassification.classify(error)
            if classification.shouldQueue {
                OfflineQueue.shared.enqueue(.expense(text: text, clientId: clientId), priority: .normal)
                let count = OfflineQueue.shared.getQueueCount()
                return (FinanceResponse(
                    success: false,
                    message: "Saved locally - will sync when online",
                    data: nil
                ), .queued(count: count))
            } else {
                return (nil, .failed(error))
            }
        }
    }

    func addTransactionOffline(merchant: String, amount: Double, category: String?, notes: String? = nil, date: Date = Date()) async -> (response: FinanceResponse?, result: OfflineOperationResult) {
        let clientId = UUID().uuidString
        do {
            let response = try await addTransactionWithClientId(merchant: merchant, amount: amount, category: category, notes: notes, date: date, clientId: clientId)
            return (response, .success)
        } catch {
            let classification = ErrorClassification.classify(error)
            if classification.shouldQueue {
                OfflineQueue.shared.enqueue(.transaction(merchant: merchant, amount: amount, category: category, clientId: clientId), priority: .normal)
                let count = OfflineQueue.shared.getQueueCount()
                return (FinanceResponse(
                    success: false,
                    message: "Saved locally - will sync when online",
                    data: nil
                ), .queued(count: count))
            } else {
                return (nil, .failed(error))
            }
        }
    }

    func addIncomeOffline(source: String, amount: Double, category: String, notes: String? = nil, date: Date = Date(), isRecurring: Bool = false) async -> (response: FinanceResponse?, result: OfflineOperationResult) {
        let clientId = UUID().uuidString
        do {
            let response = try await addIncomeWithClientId(source: source, amount: amount, category: category, notes: notes, date: date, isRecurring: isRecurring, clientId: clientId)
            return (response, .success)
        } catch {
            let classification = ErrorClassification.classify(error)
            if classification.shouldQueue {
                OfflineQueue.shared.enqueue(.income(source: source, amount: amount, category: category, clientId: clientId), priority: .normal)
                let count = OfflineQueue.shared.getQueueCount()
                return (FinanceResponse(
                    success: false,
                    message: "Saved locally - will sync when online",
                    data: nil
                ), .queued(count: count))
            } else {
                return (nil, .failed(error))
            }
        }
    }
}
