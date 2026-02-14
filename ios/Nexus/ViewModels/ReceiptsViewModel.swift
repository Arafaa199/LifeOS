import Foundation
import SwiftUI
import Combine
import os

@MainActor
class ReceiptsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "receipts")

    @Published var receipts: [ReceiptSummary] = []
    @Published var selectedReceipt: ReceiptDetail?
    @Published var nutritionSummary: ReceiptNutritionSummary?
    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var errorMessage: String?

    // MARK: - Pagination State
    @Published var receiptsPage = 0
    @Published var hasMoreReceipts = true
    @Published var isLoadingMore = false

    private let api = NexusAPI.shared
    private let financeAPI = FinanceAPI.shared

    var receiptsByMonth: [(String, [ReceiptSummary])] {
        let grouped = Dictionary(grouping: receipts) { receipt -> String in
            // Handle both "yyyy-MM-dd" and "yyyy-MM-ddTHH:mm:ss.SSSZ"
            let dateOnly = String(receipt.receipt_date.prefix(10))
            let parts = dateOnly.split(separator: "-")
            guard parts.count >= 2 else { return "Unknown" }
            return "\(parts[0])-\(parts[1])"
        }
        return grouped.sorted { $0.key > $1.key }
    }

    func loadReceipts() async {
        // Reset pagination when loading fresh data
        receiptsPage = 0
        hasMoreReceipts = true

        isLoading = true
        errorMessage = nil

        do {
            let response = try await financeAPI.fetchReceipts(offset: 0, limit: 50)
            receipts = response.receipts
            logger.info("Fetched \(response.receipts.count) receipts")

            // Check if we got fewer results than requested
            if response.receipts.count < 50 {
                hasMoreReceipts = false
            } else {
                receiptsPage += 1
            }
        } catch let decodingError as DecodingError {
            logger.logDecodingError(decodingError)
            errorMessage = "Failed to parse receipts"
        } catch {
            logger.error("Fetch receipts error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreReceipts() async {
        guard hasMoreReceipts && !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil

        do {
            let offset = receiptsPage * 50
            let response = try await financeAPI.fetchReceipts(offset: offset, limit: 50)

            // Append new receipts to existing list
            receipts.append(contentsOf: response.receipts)
            logger.info("Fetched \(response.receipts.count) more receipts")

            // Check if we got fewer results than requested
            if response.receipts.count < 50 {
                hasMoreReceipts = false
            } else {
                receiptsPage += 1
            }
        } catch let decodingError as DecodingError {
            logger.logDecodingError(decodingError)
            errorMessage = "Failed to parse receipts"
        } catch {
            logger.error("Load more receipts error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    func loadReceiptDetail(id: Int) async {
        isLoadingDetail = true
        errorMessage = nil

        do {
            let response: ReceiptDetailResponse = try await api.get("/webhook/nexus-receipt-detail?id=\(id)")
            selectedReceipt = response.receipt
            logger.info("Fetched receipt detail id=\(id) with \(response.receipt.items.count) items")

            await loadNutritionSummary(id: id)
        } catch let decodingError as DecodingError {
            logger.logDecodingError(decodingError)
            errorMessage = "Failed to parse receipt detail"
        } catch {
            logger.error("Fetch receipt detail error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoadingDetail = false
    }

    func loadNutritionSummary(id: Int) async {
        do {
            let response: ReceiptNutritionResponse = try await api.get("/webhook/nexus-receipt-nutrition?id=\(id)")
            nutritionSummary = response.nutrition
        } catch {
            logger.error("Fetch nutrition summary error: \(error.localizedDescription)")
        }
    }

    func matchItemToFood(itemId: Int, foodId: Int) async -> Bool {
        errorMessage = nil

        let request = ReceiptItemMatchRequest(
            item_id: itemId,
            food_id: foodId,
            is_user_confirmed: true
        )

        do {
            let response: ReceiptItemMatchResponse = try await api.post(
                "/webhook/nexus-receipt-item-match",
                body: request,
                decoder: JSONDecoder()
            )

            if response.success {
                logger.info("Matched item \(itemId) to food \(foodId)")

                if let receiptId = selectedReceipt?.id {
                    await loadReceiptDetail(id: receiptId)
                }
                return true
            } else {
                errorMessage = "Failed to match item"
                return false
            }
        } catch {
            logger.error("Match item error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func formatMonthHeader(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return key }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return key
    }
}
