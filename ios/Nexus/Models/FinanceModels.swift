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
    let clientId: String?

    init(text: String, clientId: String? = nil) {
        self.text = text
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case text
        case clientId = "client_id"
    }
}

// MARK: - Transaction Request

struct AddTransactionRequest: Codable {
    let merchantName: String
    let amount: Double
    let category: String?
    let notes: String?
    let date: String?
    let clientId: String?

    init(merchantName: String, amount: Double, category: String? = nil, notes: String? = nil, date: String? = nil, clientId: String? = nil) {
        self.merchantName = merchantName
        self.amount = amount
        self.category = category
        self.notes = notes
        self.date = date
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case merchantName = "merchant_name"
        case amount
        case category
        case notes
        case date
        case clientId = "client_id"
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
    let date: String?
    let isRecurring: Bool
    let clientId: String?

    init(source: String, amount: Double, category: String, notes: String? = nil, date: String? = nil, isRecurring: Bool = false, clientId: String? = nil) {
        self.source = source
        self.amount = amount
        self.category = category
        self.notes = notes
        self.date = date
        self.isRecurring = isRecurring
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case source
        case amount
        case category
        case notes
        case date
        case isRecurring = "is_recurring"
        case clientId = "client_id"
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

// MARK: - Installment Plan (BNPL)

struct InstallmentPlan: Identifiable, Codable {
    let id: Int
    let source: String
    let merchant: String
    let totalAmount: Double
    let installmentsTotal: Int
    let installmentsPaid: Int
    let installmentAmount: Double
    let currency: String
    let purchaseDate: Date?
    let nextDueDate: Date?
    let finalDueDate: Date?
    let status: String
    let remainingPayments: Int
    let remainingAmount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case merchant
        case totalAmount = "total_amount"
        case installmentsTotal = "installments_total"
        case installmentsPaid = "installments_paid"
        case installmentAmount = "installment_amount"
        case currency
        case purchaseDate = "purchase_date"
        case nextDueDate = "next_due_date"
        case finalDueDate = "final_due_date"
        case status
        case remainingPayments = "remaining_payments"
        case remainingAmount = "remaining_amount"
    }

    var progress: String {
        "\(installmentsPaid)/\(installmentsTotal)"
    }

    var sourceIcon: String {
        switch source.lowercased() {
        case "tabby": return "creditcard.fill"
        case "tamara": return "creditcard.fill"
        case "postpay": return "creditcard.fill"
        default: return "calendar.badge.clock"
        }
    }

    var sourceColor: String {
        switch source.lowercased() {
        case "tabby": return "purple"
        case "tamara": return "blue"
        case "postpay": return "green"
        default: return "gray"
        }
    }

    var isDueSoon: Bool {
        guard let nextDue = nextDueDate else { return false }
        let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: nextDue).day ?? 0
        return daysUntilDue <= 7 && daysUntilDue >= 0
    }

    var isOverdue: Bool {
        guard let nextDue = nextDueDate else { return false }
        return nextDue < Date()
    }
}

struct InstallmentsResponse: Codable {
    let plans: [InstallmentPlan]
    let summary: InstallmentsSummary
}

struct InstallmentsSummary: Codable {
    let activePlans: Int
    let totalRemaining: String
    let dueThisWeek: Int
    let dueThisWeekAmount: String

    enum CodingKeys: String, CodingKey {
        case activePlans = "active_plans"
        case totalRemaining = "total_remaining"
        case dueThisWeek = "due_this_week"
        case dueThisWeekAmount = "due_this_week_amount"
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

// MARK: - Finance Planning Models

struct Category: Identifiable, Codable {
    let id: Int
    let name: String
    let type: String  // "expense" or "income"
    let icon: String?
    let color: String?
    let keywords: [String]?
    let isActive: Bool
    let displayOrder: Int
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, icon, color, keywords
        case isActive = "is_active"
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isExpense: Bool { type == "expense" }
    var isIncome: Bool { type == "income" }

    var displayIcon: String {
        icon ?? (isExpense ? "minus.circle" : "plus.circle")
    }
}

struct RecurringItem: Identifiable, Codable {
    let id: Int
    let name: String
    let amount: Double
    let currency: String
    let type: String  // "expense" or "income"
    let cadence: String  // daily, weekly, biweekly, monthly, quarterly, yearly
    let dayOfMonth: Int?
    let dayOfWeek: Int?
    let nextDueDate: Date?
    let lastOccurrence: Date?
    let categoryId: Int?
    let merchantPattern: String?
    let isActive: Bool
    let autoCreate: Bool
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, amount, currency, type, cadence, notes
        case dayOfMonth = "day_of_month"
        case dayOfWeek = "day_of_week"
        case nextDueDate = "next_due_date"
        case lastOccurrence = "last_occurrence"
        case categoryId = "category_id"
        case merchantPattern = "merchant_pattern"
        case isActive = "is_active"
        case autoCreate = "auto_create"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isExpense: Bool { type == "expense" }
    var isIncome: Bool { type == "income" }

    var cadenceDisplay: String {
        switch cadence {
        case "daily": return "Daily"
        case "weekly": return "Weekly"
        case "biweekly": return "Every 2 weeks"
        case "monthly": return "Monthly"
        case "quarterly": return "Quarterly"
        case "yearly": return "Yearly"
        default: return cadence.capitalized
        }
    }

    var daysUntilDue: Int? {
        guard let nextDue = nextDueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: nextDue).day
    }

    var isDueSoon: Bool {
        guard let days = daysUntilDue else { return false }
        return days >= 0 && days <= 7
    }

    var isOverdue: Bool {
        guard let days = daysUntilDue else { return false }
        return days < 0
    }
}

struct MatchingRule: Identifiable, Codable {
    let id: Int
    let merchantPattern: String
    let category: String?
    let subcategory: String?
    let storeName: String?
    let isGrocery: Bool
    let isRestaurant: Bool
    let isFoodRelated: Bool
    let priority: Int
    let categoryId: Int?
    let confidence: Int
    let matchCount: Int
    let lastMatchedAt: Date?
    let isActive: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, category, subcategory, priority, confidence, notes
        case merchantPattern = "merchant_pattern"
        case storeName = "store_name"
        case isGrocery = "is_grocery"
        case isRestaurant = "is_restaurant"
        case isFoodRelated = "is_food_related"
        case categoryId = "category_id"
        case matchCount = "match_count"
        case lastMatchedAt = "last_matched_at"
        case isActive = "is_active"
    }

    var confidenceDisplay: String {
        "\(confidence)%"
    }

    var hasMatches: Bool {
        matchCount > 0
    }
}

// MARK: - Finance Planning Requests

struct CreateCategoryRequest: Codable {
    let name: String
    let type: String
    let icon: String?
    let color: String?
    let keywords: [String]?
    let displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case name, type, icon, color, keywords
        case displayOrder = "display_order"
    }
}

struct CreateRecurringItemRequest: Codable {
    let name: String
    let amount: Double
    let currency: String?
    let type: String
    let cadence: String
    let dayOfMonth: Int?
    let dayOfWeek: Int?
    let nextDueDate: String?
    let categoryId: Int?
    let merchantPattern: String?
    let autoCreate: Bool?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, amount, currency, type, cadence, notes
        case dayOfMonth = "day_of_month"
        case dayOfWeek = "day_of_week"
        case nextDueDate = "next_due_date"
        case categoryId = "category_id"
        case merchantPattern = "merchant_pattern"
        case autoCreate = "auto_create"
    }
}

struct CreateMatchingRuleRequest: Codable {
    let merchantPattern: String
    let category: String?
    let subcategory: String?
    let storeName: String?
    let isGrocery: Bool?
    let isRestaurant: Bool?
    let isFoodRelated: Bool?
    let priority: Int?
    let categoryId: Int?
    let confidence: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case category, subcategory, priority, confidence, notes
        case merchantPattern = "merchant_pattern"
        case storeName = "store_name"
        case isGrocery = "is_grocery"
        case isRestaurant = "is_restaurant"
        case isFoodRelated = "is_food_related"
        case categoryId = "category_id"
    }
}

struct CreateBudgetRequest: Codable {
    let month: String
    let category: String
    let budgetAmount: Double
    let categoryId: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case month, category, notes
        case budgetAmount = "budget_amount"
        case categoryId = "category_id"
    }
}

// MARK: - Finance Planning Responses

struct CategoriesResponse: Codable {
    let success: Bool
    let data: [Category]?
    let message: String?
}

struct RecurringItemsResponse: Codable {
    let success: Bool
    let data: [RecurringItem]?
    let message: String?
}

struct MatchingRulesResponse: Codable {
    let success: Bool
    let data: [MatchingRule]?
    let message: String?
}

struct SingleItemResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
}

struct DeleteResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - LifeOS Daily Summary Response

struct FinanceDailySummaryResponse: Codable {
    let date: String
    let health: HealthSummary?
    let finance: FinanceDaySummary?
    let behavior: BehaviorSummary?
    let anomalies: [Anomaly]?
    let confidence: Double?
    let dataCoverage: DataCoverage?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case date, health, finance, behavior, anomalies, confidence
        case dataCoverage = "data_coverage"
        case generatedAt = "generated_at"
    }
}

struct HealthSummary: Codable {
    let sleepHours: Double?
    let recovery: Int?
    let hrv: Double?
    let rhr: Int?
    let strain: Double?
    let weight: Double?
    let sleepPerformance: Int?

    enum CodingKeys: String, CodingKey {
        case recovery, hrv, rhr, strain, weight
        case sleepHours = "sleep_hours"
        case sleepPerformance = "sleep_performance"
    }
}

struct FinanceDaySummary: Codable {
    let totalSpent: Double?
    let totalIncome: Double?
    let topCategories: [CategorySpend]?
    let largestTx: LargestTransaction?
    let isExpensiveDay: Bool?
    let spendScore: Int?
    let transactionCount: Int?

    enum CodingKeys: String, CodingKey {
        case topCategories = "top_categories"
        case largestTx = "largest_tx"
        case isExpensiveDay = "is_expensive_day"
        case spendScore = "spend_score"
        case transactionCount = "transaction_count"
        case totalSpent = "total_spent"
        case totalIncome = "total_income"
    }
}

struct CategorySpend: Codable {
    let category: String
    let spent: Double
}

struct LargestTransaction: Codable {
    let amount: Double?
    let merchant: String?
    let category: String?
}

struct BehaviorSummary: Codable {
    let leftHomeAt: String?
    let returnedHomeAt: String?
    let hoursAtHome: Double?
    let hoursAway: Double?
    let tvMinutes: Int?
    let screenLate: Bool?

    enum CodingKeys: String, CodingKey {
        case leftHomeAt = "left_home_at"
        case returnedHomeAt = "returned_home_at"
        case hoursAtHome = "hours_at_home"
        case hoursAway = "hours_away"
        case tvMinutes = "tv_minutes"
        case screenLate = "screen_late"
    }
}

struct Anomaly: Codable {
    let type: String
    let reason: String?
    let explanation: String?
    let confidence: Double?
    let metrics: AnomalyMetrics?
}

struct AnomalyMetrics: Codable {
    let value: Double?
    let baseline: Double?
    let zScore: Double?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case value, baseline, unit
        case zScore = "z_score"
    }
}

struct DataCoverage: Codable {
    let sms: Bool?
    let receipts: Bool?
    let health: Bool?
    let staleFeeds: Int?

    enum CodingKeys: String, CodingKey {
        case sms, receipts, health
        case staleFeeds = "stale_feeds"
    }
}

// MARK: - Weekly Report Response

struct WeeklyReportResponse: Codable {
    let success: Bool
    let weekStart: String?
    let weekEnd: String?
    let reportMarkdown: String?
    let dataCompleteness: Double?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case reportMarkdown = "report_markdown"
        case dataCompleteness = "data_completeness"
        case generatedAt = "generated_at"
    }
}

// MARK: - System Health Response

struct SystemHealthResponse: Codable {
    let feeds: [SystemFeedStatus]?
    let feedsOk: Int?
    let feedsStale: Int?
    let feedsCritical: Int?
    let feedsTotal: Int?
    let overallStatus: String?

    enum CodingKeys: String, CodingKey {
        case feeds
        case feedsOk = "feeds_ok"
        case feedsStale = "feeds_stale"
        case feedsCritical = "feeds_critical"
        case feedsTotal = "feeds_total"
        case overallStatus = "overall_status"
    }
}

struct SystemFeedStatus: Codable, Identifiable {
    var id: String { feedName }
    let feedName: String
    let lastEventAt: String?
    let hoursSince: Double?
    let expectedFrequencyHours: Double?
    let status: String
    let domain: String?
    let events24h: Int?

    enum CodingKeys: String, CodingKey {
        case status, domain
        case feedName = "feed_name"
        case lastEventAt = "last_event_at"
        case hoursSince = "hours_since"
        case expectedFrequencyHours = "expected_frequency_hours"
        case events24h = "events_24h"
    }

    var statusColor: String {
        switch status.uppercased() {
        case "OK": return "green"
        case "STALE": return "yellow"
        case "CRITICAL": return "red"
        default: return "gray"
        }
    }
}
