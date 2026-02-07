import Foundation

// MARK: - Receipt Summary (List View)

struct ReceiptSummary: Codable, Identifiable, Sendable {
    let id: Int
    let vendor: String
    let store_name: String?
    let receipt_date: String
    let total_amount: Double
    let currency: String
    let parse_status: String?
    let linked_transaction_id: Int?
    let item_count: Int
    let matched_count: Int
}

struct ReceiptsResponse: Codable, Sendable {
    let success: Bool
    let receipts: [ReceiptSummary]
    let count: Int
}

// MARK: - Receipt Detail

struct ReceiptDetail: Codable, Identifiable, Sendable {
    let id: Int
    let vendor: String
    let store_name: String?
    let store_address: String?
    let receipt_date: String
    let receipt_time: String?
    let invoice_number: String?
    let subtotal: Double?
    let vat_amount: Double?
    let total_amount: Double
    let currency: String
    let linked_transaction_id: Int?
    let link_method: String?
    let items: [ReceiptItem]
}

struct ReceiptDetailResponse: Codable, Sendable {
    let success: Bool
    let receipt: ReceiptDetail
}

// MARK: - Receipt Item

struct ReceiptItem: Codable, Identifiable, Sendable {
    let id: Int
    let line_number: Int?
    let item_description: String
    let item_description_clean: String?
    let quantity: Double?
    let unit: String?
    let unit_price: Double?
    let line_total: Double
    let is_promotional: Bool?
    let discount_amount: Double?
    let matched_food_id: Int?
    let match_confidence: Double?
    let is_user_confirmed: Bool?
    let food_name: String?
    let food_brand: String?
    let calories_per_100g: Double?
    let protein_per_100g: Double?
    let carbs_per_100g: Double?
    let fat_per_100g: Double?
    let serving_size_g: Double?

    var isMatched: Bool {
        matched_food_id != nil
    }

    var displayDescription: String {
        item_description_clean ?? item_description
    }
}

// MARK: - Item Match

struct ReceiptItemMatchRequest: Codable, Sendable {
    let item_id: Int
    let food_id: Int
    let is_user_confirmed: Bool
}

struct ReceiptItemMatchResponse: Codable, Sendable {
    let success: Bool
    let item: ReceiptItemMatchResult?
}

struct ReceiptItemMatchResult: Codable, Sendable {
    let id: Int
    let matched_food_id: Int
    let match_confidence: Double
    let is_user_confirmed: Bool
}

// MARK: - Nutrition Summary

struct ReceiptNutritionResponse: Codable, Sendable {
    let success: Bool
    let nutrition: ReceiptNutritionSummary
}

struct ReceiptNutritionSummary: Codable, Sendable {
    let total_items: Int
    let matched_items: Int
    let total_calories: Double
    let total_protein: Double
    let total_carbs: Double
    let total_fat: Double
}
