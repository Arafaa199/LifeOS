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

    private let api = NexusAPI.shared

    var receiptsByMonth: [(String, [ReceiptSummary])] {
        let grouped = Dictionary(grouping: receipts) { receipt -> String in
            let parts = receipt.receipt_date.split(separator: "-")
            guard parts.count >= 2 else { return "Unknown" }
            let year = String(parts[0])
            let month = String(parts[1])
            return "\(year)-\(month)"
        }
        return grouped.sorted { $0.key > $1.key }
    }

    func loadReceipts() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: ReceiptsResponse = try await api.get("/webhook/nexus-receipts")
            receipts = response.receipts
            logger.info("Fetched \(response.count) receipts")
        } catch let decodingError as DecodingError {
            logDecodingError(decodingError)
            errorMessage = "Failed to parse receipts"
        } catch {
            logger.error("Fetch receipts error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
            logDecodingError(decodingError)
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

    private func logDecodingError(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let context):
            logger.error("Decode TypeMismatch: expected \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .keyNotFound(let key, let context):
            logger.error("Decode KeyNotFound: \(key.stringValue), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .valueNotFound(let type, let context):
            logger.error("Decode ValueNotFound: \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .dataCorrupted(let context):
            logger.error("Decode DataCorrupted: \(context.debugDescription)")
        @unknown default:
            logger.error("Decode unknown error: \(error.localizedDescription)")
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
