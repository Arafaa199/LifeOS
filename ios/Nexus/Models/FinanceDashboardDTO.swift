import Foundation

// MARK: - Finance Dashboard DTO
// Single endpoint: GET /app/finance
// Returns everything needed for the Finance tab in one call

struct FinanceDashboardDTO: Codable {
    let meta: FinanceMeta
    let today: FinanceTodayDTO
    let month: FinanceMonthDTO
    let recent: [FinanceTransactionDTO]
    let insight: FinanceInsightDTO?

    enum CodingKeys: String, CodingKey {
        case meta, today, month, recent, insight
    }
}

struct FinanceMeta: Codable {
    let generatedAt: Date
    let timezone: String
    let currency: String

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone, currency
    }
}

// MARK: - Today Section

struct FinanceTodayDTO: Codable {
    let spent: Double
    let transactionCount: Int
    let vsYesterday: Double?          // Percentage change vs yesterday
    let vsAverage7d: Double?          // Percentage change vs 7-day avg
    let isUnusual: Bool

    enum CodingKeys: String, CodingKey {
        case spent
        case transactionCount = "transaction_count"
        case vsYesterday = "vs_yesterday"
        case vsAverage7d = "vs_average_7d"
        case isUnusual = "is_unusual"
    }
}

// MARK: - Month Section

struct FinanceMonthDTO: Codable {
    let spent: Double
    let income: Double
    let budget: Double?
    let budgetUsedPercent: Double?
    let daysRemaining: Int
    let projectedTotal: Double?
    let categories: [FinanceCategoryDTO]

    enum CodingKeys: String, CodingKey {
        case spent, income, budget
        case budgetUsedPercent = "budget_used_percent"
        case daysRemaining = "days_remaining"
        case projectedTotal = "projected_total"
        case categories
    }

    var net: Double {
        income - spent
    }

    var budgetRemaining: Double? {
        guard let budget = budget else { return nil }
        return budget - spent
    }
}

struct FinanceCategoryDTO: Codable, Identifiable {
    var id: String { name }

    let name: String
    let spent: Double
    let budget: Double?
    let percentOfTotal: Double
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case name, spent, budget
        case percentOfTotal = "percent_of_total"
        case icon
    }

    var budgetUsedPercent: Double? {
        guard let budget = budget, budget > 0 else { return nil }
        return (spent / budget) * 100
    }
}

// MARK: - Transaction

struct FinanceTransactionDTO: Codable, Identifiable {
    let id: Int
    let date: Date
    let time: String
    let merchant: String
    let amount: Double
    let category: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, date, time, merchant, amount, category, source
    }

    var isExpense: Bool {
        amount < 0
    }
}

// MARK: - Insight

struct FinanceInsightDTO: Codable, Identifiable {
    var id: String { type }

    let type: String
    let title: String
    let detail: String
    let icon: String
    let severity: InsightSeverity

    enum InsightSeverity: String, Codable {
        case info
        case warning
        case alert
    }
}

// MARK: - API Response Wrapper

struct FinanceDashboardResponse: Codable {
    let success: Bool
    let data: FinanceDashboardDTO?
    let error: String?

    // Handle both wrapped and unwrapped responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.success) {
            success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
            data = try container.decodeIfPresent(FinanceDashboardDTO.self, forKey: .data)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        } else {
            // Direct payload without wrapper
            success = true
            data = try FinanceDashboardDTO(from: decoder)
            error = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, data, error
    }
}

// MARK: - Preview Fixtures

extension FinanceDashboardDTO {
    static let preview: FinanceDashboardDTO = {
        let dubaiTZ = TimeZone(identifier: "Asia/Dubai")!
        let calendar = Calendar.current

        return FinanceDashboardDTO(
            meta: FinanceMeta(
                generatedAt: Date(),
                timezone: "Asia/Dubai",
                currency: "AED"
            ),
            today: FinanceTodayDTO(
                spent: 287.50,
                transactionCount: 4,
                vsYesterday: 15.2,
                vsAverage7d: -8.5,
                isUnusual: false
            ),
            month: FinanceMonthDTO(
                spent: 4_235.80,
                income: 12_500.00,
                budget: 8_000.00,
                budgetUsedPercent: 52.9,
                daysRemaining: 12,
                projectedTotal: 6_800.00,
                categories: [
                    FinanceCategoryDTO(name: "Grocery", spent: 1_450.00, budget: 2_000.00, percentOfTotal: 34.2, icon: "cart.fill"),
                    FinanceCategoryDTO(name: "Restaurant", spent: 980.50, budget: 1_500.00, percentOfTotal: 23.1, icon: "fork.knife"),
                    FinanceCategoryDTO(name: "Transport", spent: 620.30, budget: 800.00, percentOfTotal: 14.6, icon: "car.fill")
                ]
            ),
            recent: [
                FinanceTransactionDTO(id: 1, date: Date(), time: "14:32", merchant: "Carrefour", amount: -125.50, category: "Grocery", source: "sms"),
                FinanceTransactionDTO(id: 2, date: Date(), time: "12:15", merchant: "Talabat", amount: -62.00, category: "Restaurant", source: "sms"),
                FinanceTransactionDTO(id: 3, date: Date(), time: "09:30", merchant: "ENOC", amount: -100.00, category: "Transport", source: "sms"),
                FinanceTransactionDTO(id: 4, date: calendar.date(byAdding: .day, value: -1, to: Date())!, time: "18:45", merchant: "Spinneys", amount: -89.75, category: "Grocery", source: "sms"),
                FinanceTransactionDTO(id: 5, date: calendar.date(byAdding: .day, value: -1, to: Date())!, time: "13:20", merchant: "Starbucks", amount: -42.00, category: "Restaurant", source: "manual")
            ],
            insight: FinanceInsightDTO(
                type: "category_high",
                title: "Grocery spending on track",
                detail: "You've used 72% of your grocery budget with 12 days left.",
                icon: "cart.fill",
                severity: .info
            )
        )
    }()

    static let empty: FinanceDashboardDTO = {
        FinanceDashboardDTO(
            meta: FinanceMeta(generatedAt: Date(), timezone: "Asia/Dubai", currency: "AED"),
            today: FinanceTodayDTO(spent: 0, transactionCount: 0, vsYesterday: nil, vsAverage7d: nil, isUnusual: false),
            month: FinanceMonthDTO(spent: 0, income: 0, budget: nil, budgetUsedPercent: nil, daysRemaining: 15, projectedTotal: nil, categories: []),
            recent: [],
            insight: nil
        )
    }()
}
