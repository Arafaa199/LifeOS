import Foundation

// MARK: - Receipt Response

struct ReceiptsResponse: Codable {
    let success: Bool
    let receipts: [Receipt]
}

// MARK: - Receipt

struct Receipt: Codable, Identifiable {
    let id: Int
    let vendor: String?
    let storeLocation: String?
    let receiptDate: String?
    let total: Double
    let status: String?
    let createdAt: String?
    let items: [ReceiptItem]

    var displayDate: String {
        guard let dateStr = receiptDate ?? createdAt else { return "Unknown" }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: dateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }

        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }

        // Fallback: just return date portion
        return String(dateStr.prefix(10))
    }

    var displayVendor: String {
        vendor ?? "Unknown Store"
    }

    var itemCount: Int {
        items.count
    }
}

// MARK: - Receipt Item

struct ReceiptItem: Codable, Identifiable {
    let id: Int
    let name: String?
    let brand: String?
    let qty: Double?
    let unitPrice: Double?
    let total: Double?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, qty, total, category
        case unitPrice = "unit_price"
    }

    var displayName: String {
        if let brand = brand, !brand.isEmpty, brand != name {
            return "\(brand) - \(name ?? "Item")"
        }
        return name ?? "Unknown Item"
    }

    var displayQty: String {
        guard let qty = qty, qty > 1 else { return "" }
        if qty == qty.rounded() {
            return "\(Int(qty))x"
        }
        return String(format: "%.2fx", qty)
    }

    var displayTotal: String {
        guard let total = total else { return "" }
        return String(format: "%.2f AED", total)
    }
}
