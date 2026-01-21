import Foundation

// MARK: - Finance Models

struct Transaction: Identifiable, Codable {
    let id: Int?
    let date: Date
    let merchantName: String
    let amount: Double
    let currency: String
    let category: String?
    let subcategory: String?
    let isGrocery: Bool
    let isRestaurant: Bool
    let notes: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case merchantName = "merchant_name"
        case amount
        case currency
        case category
        case subcategory
        case isGrocery = "is_grocery"
        case isRestaurant = "is_restaurant"
        case notes
        case tags
    }

    var displayAmount: String {
        let absAmount = abs(amount)
        return String(format: "%@ %.2f", currency, absAmount)
    }

    /// Returns a normalized copy with cleaned merchant name and corrected category
    func normalized() -> Transaction {
        let cleanedMerchant = Self.normalizeMerchantName(merchantName)
        let correctedCategory = Self.inferCategory(
            merchant: cleanedMerchant,
            originalCategory: category,
            amount: amount
        )

        return Transaction(
            id: id,
            date: date,
            merchantName: cleanedMerchant,
            amount: amount,
            currency: currency,
            category: correctedCategory,
            subcategory: subcategory,
            isGrocery: correctedCategory == "Grocery",
            isRestaurant: correctedCategory == "Restaurant",
            notes: notes,
            tags: tags
        )
    }

    // MARK: - Merchant Name Normalization

    private static let merchantNameMapping: [String: String] = [
        // Careem variants
        "CAREEM QUIK": "Careem Quik",
        "CAREEM FOOD": "Careem Food",
        "CAREEMQUIK": "Careem Quik",
        "CAREEMFOOD": "Careem Food",
        "CAREEM": "Careem",
        // Grocery
        "CARREFOUR": "Carrefour",
        "LULU": "Lulu Hypermarket",
        "CHOITHRAMS": "Choithrams",
        "SPINNEYS": "Spinneys",
        "VIVA": "Viva Supermarket",
        "UNION COOP": "Union Coop",
        // Food delivery
        "TALABAT": "Talabat",
        "DELIVEROO": "Deliveroo",
        "NOON FOOD": "Noon Food",
        "ZOMATO": "Zomato",
        // Transport
        "UBER": "Uber",
        "SALIK": "Salik",
        "RTA": "RTA",
        "ENOC": "ENOC",
        "ADNOC": "ADNOC",
        // Utilities
        "DEWA": "DEWA",
        "ETISALAT": "Etisalat",
        "DU": "du"
    ]

    private static func normalizeMerchantName(_ name: String) -> String {
        let upper = name.uppercased().trimmingCharacters(in: .whitespaces)

        // Check direct mapping
        for (pattern, normalized) in merchantNameMapping {
            if upper.contains(pattern) {
                return normalized
            }
        }

        // Clean up bank entries
        if upper.contains("EMIRATESNBD") || upper.contains("EMIRATES NBD") {
            let cleaned = name
                .replacingOccurrences(of: "EmiratesNBD", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Emirates NBD", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty && cleaned.count > 3 {
                return cleaned
            }
            return "Emirates NBD Transfer"
        }

        if upper.contains("ALRAJHI") || upper.contains("AL RAJHI") {
            let cleaned = name
                .replacingOccurrences(of: "AlRajhiBank", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Al Rajhi Bank", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty && cleaned.count > 3 {
                return cleaned
            }
            return "Al Rajhi Transfer"
        }

        return name
    }

    // MARK: - Category Inference

    private static let categoryMapping: [String: String] = [
        // Grocery
        "Carrefour": "Grocery", "Lulu": "Grocery", "Choithrams": "Grocery",
        "Spinneys": "Grocery", "Viva": "Grocery", "Union Coop": "Grocery",
        // Restaurant/Food
        "Talabat": "Restaurant", "Deliveroo": "Restaurant", "Careem Food": "Restaurant",
        "Noon Food": "Restaurant", "Zomato": "Restaurant",
        // Transport
        "Uber": "Transport", "Careem": "Transport", "Salik": "Transport",
        "RTA": "Transport", "ENOC": "Transport", "ADNOC": "Transport",
        // Utilities
        "DEWA": "Utilities", "Etisalat": "Utilities", "du": "Utilities"
    ]

    private static func inferCategory(merchant: String, originalCategory: String?, amount: Double) -> String? {
        // If already categorized and not "Other", keep it
        if let original = originalCategory, original != "Other" && !original.isEmpty {
            return original
        }

        // Try to infer from merchant name
        for (merchantKey, category) in categoryMapping {
            if merchant.lowercased().contains(merchantKey.lowercased()) {
                return category
            }
        }

        return originalCategory
    }
}

struct Account: Identifiable, Codable {
    let id: Int
    let name: String
    let institution: String?
    let accountType: String?
    let lastFour: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case institution
        case accountType = "account_type"
        case lastFour = "last_four"
        case isActive = "is_active"
    }
}

struct Budget: Identifiable, Codable {
    let id: Int?
    let month: String
    let category: String
    let budgetAmount: Double
    let spent: Double?
    let remaining: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case month
        case category
        case budgetAmount = "budget_amount"
        case spent
        case remaining
    }
}

struct FinanceSummary: Codable {
    var totalSpent: Double
    var grocerySpent: Double
    var eatingOutSpent: Double
    var currency: String
    var categoryBreakdown: [String: Double]
    var recentTransactions: [Transaction]
    var budgets: [Budget]

    init() {
        totalSpent = 0
        grocerySpent = 0
        eatingOutSpent = 0
        currency = "AED"  // Default to AED
        categoryBreakdown = [:]
        recentTransactions = []
        budgets = []
    }

    func formatAmount(_ amount: Double) -> String {
        return String(format: "%@ %.2f", currency, abs(amount))
    }
}

// MARK: - Quick Expense Log Request

struct QuickExpenseRequest: Codable {
    let text: String
}

// MARK: - Transaction Request

struct AddTransactionRequest: Codable {
    let merchantName: String
    let amount: Double
    let category: String?
    let notes: String?
    let date: String?  // ISO8601 format

    enum CodingKeys: String, CodingKey {
        case merchantName = "merchant_name"
        case amount
        case category
        case notes
        case date
    }
}

struct UpdateTransactionRequest: Codable {
    let id: Int
    let merchantName: String
    let amount: Double
    let category: String?
    let notes: String?
    let date: String?  // ISO8601 format

    enum CodingKeys: String, CodingKey {
        case id
        case merchantName = "merchant_name"
        case amount
        case category
        case notes
        case date
    }
}

struct AddIncomeRequest: Codable {
    let source: String
    let amount: Double
    let category: String
    let notes: String?
    let date: String?  // ISO8601 format
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case source
        case amount
        case category
        case notes
        case date
        case isRecurring = "is_recurring"
    }
}

// MARK: - Finance Response

struct FinanceResponse: Codable {
    let success: Bool
    let message: String?
    let data: FinanceResponseData?
}

struct FinanceResponseData: Codable {
    let transaction: Transaction?
    let totalSpent: Double?
    let categorySpent: Double?
    let grocerySpent: Double?
    let eatingOutSpent: Double?
    let currency: String?
    let recentTransactions: [Transaction]?
    let budgets: [Budget]?
    let categoryBreakdown: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case transaction
        case totalSpent = "total_spent"
        case categorySpent = "category_spent"
        case grocerySpent = "grocery_spent"
        case eatingOutSpent = "eating_out_spent"
        case currency
        case recentTransactions = "recent_transactions"
        case budgets
        case categoryBreakdown = "category_breakdown"
    }
}

// MARK: - Budget Request/Response

struct SetBudgetRequest: Codable {
    let category: String
    let amount: Double
}

struct BudgetResponse: Codable {
    let success: Bool
    let message: String?
    let data: BudgetResponseData?
}

struct BudgetResponseData: Codable {
    let budget: Budget
}

struct BudgetsResponse: Codable {
    let success: Bool
    let data: BudgetsData?
}

struct BudgetsData: Codable {
    let budgets: [Budget]
}

// MARK: - Insights Request/Response

struct InsightsRequest: Codable {
    let summary: String
}

struct InsightsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InsightsData?
}

struct InsightsData: Codable {
    let insights: String?
}

// MARK: - Monthly Trends Response

struct MonthlyTrendsResponse: Codable {
    let success: Bool
    let data: MonthlyTrendsData?
}

struct MonthlyTrendsData: Codable {
    let monthlySpending: [MonthlySpending]

    enum CodingKeys: String, CodingKey {
        case monthlySpending = "monthly_spending"
    }
}

struct MonthlySpending: Identifiable, Codable {
    let id: Int?
    let month: String
    let totalSpent: Double
    let categoryBreakdown: [String: Double]

    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: month) {
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
        return month
    }

    enum CodingKeys: String, CodingKey {
        case id
        case month
        case totalSpent = "total_spent"
        case categoryBreakdown = "category_breakdown"
    }
}

// MARK: - Expense Categories

enum ExpenseCategory: String, CaseIterable {
    case grocery = "Grocery"
    case restaurant = "Restaurant"
    case transport = "Transport"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case health = "Health"
    case shopping = "Shopping"
    case other = "Other"

    var icon: String {
        switch self {
        case .grocery: return "cart.fill"
        case .restaurant: return "fork.knife"
        case .transport: return "car.fill"
        case .utilities: return "house.fill"
        case .entertainment: return "tv.fill"
        case .health: return "heart.fill"
        case .shopping: return "bag.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
