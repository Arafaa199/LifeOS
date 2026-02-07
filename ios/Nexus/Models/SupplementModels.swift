import Foundation

// MARK: - Supplement Definition

struct Supplement: Codable, Identifiable {
    let id: Int
    let name: String
    let brand: String?
    let doseAmount: Double?
    let doseUnit: String?
    let frequency: String
    let timesOfDay: [String]
    let category: String
    let notes: String?
    let active: Bool
    let startDate: String?
    let endDate: String?
    var todayDoses: [SupplementDoseStatus]?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, frequency, category, notes, active
        case doseAmount = "dose_amount"
        case doseUnit = "dose_unit"
        case timesOfDay = "times_of_day"
        case startDate = "start_date"
        case endDate = "end_date"
        case todayDoses = "today_doses"
    }

    var displayDose: String {
        guard let amount = doseAmount, let unit = doseUnit else { return "" }
        if amount == floor(amount) {
            return "\(Int(amount)) \(unit)"
        }
        return "\(amount) \(unit)"
    }

    var categoryIcon: String {
        switch category {
        case "vitamin": return "pill.fill"
        case "mineral": return "leaf.fill"
        case "medication": return "cross.case.fill"
        case "probiotic": return "allergens"
        case "herb": return "leaf.arrow.triangle.circlepath"
        default: return "pills.fill"
        }
    }

    var frequencyDisplay: String {
        switch frequency {
        case "daily": return "Daily"
        case "twice_daily": return "Twice daily"
        case "three_times_daily": return "3x daily"
        case "weekly": return "Weekly"
        case "as_needed": return "As needed"
        default: return frequency.capitalized
        }
    }

    var todayStatus: String {
        guard let doses = todayDoses, !doses.isEmpty else { return "pending" }
        if doses.allSatisfy({ $0.status == "taken" }) { return "taken" }
        if doses.contains(where: { $0.status == "taken" }) { return "partial" }
        if doses.allSatisfy({ $0.status == "skipped" }) { return "skipped" }
        return "pending"
    }
}

struct SupplementDoseStatus: Codable {
    let timeSlot: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case timeSlot = "time_slot"
        case status
    }
}

// MARK: - API Responses

struct SupplementsResponse: Codable {
    let supplements: [Supplement]
    let summary: SupplementsSummary
}

struct SupplementsSummary: Codable {
    let totalSupplements: Int
    let totalDosesToday: Int
    let taken: Int
    let skipped: Int
    let pending: Int
    let adherencePct: Int?

    enum CodingKeys: String, CodingKey {
        case totalSupplements = "total_supplements"
        case totalDosesToday = "total_doses_today"
        case taken, skipped, pending
        case adherencePct = "adherence_pct"
    }
}

struct SupplementLogResponse: Codable {
    let success: Bool
    let medicationId: Int
    let summary: SupplementLogSummary

    enum CodingKeys: String, CodingKey {
        case success
        case medicationId = "medication_id"
        case summary
    }
}

struct SupplementLogSummary: Codable {
    let takenToday: Int
    let skippedToday: Int
    let pendingToday: Int

    enum CodingKeys: String, CodingKey {
        case takenToday = "taken_today"
        case skippedToday = "skipped_today"
        case pendingToday = "pending_today"
    }
}

struct SupplementUpsertResponse: Codable {
    let success: Bool
    let action: String
    let supplement: Supplement
}

// MARK: - Request Models

struct SupplementCreateRequest: Codable {
    let name: String
    let brand: String?
    let doseAmount: Double?
    let doseUnit: String?
    let frequency: String
    let timesOfDay: [String]
    let category: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, brand, frequency, category, notes
        case doseAmount = "dose_amount"
        case doseUnit = "dose_unit"
        case timesOfDay = "times_of_day"
    }
}

struct SupplementLogRequest: Codable {
    let supplementId: Int
    let status: String
    let timeSlot: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case supplementId = "supplement_id"
        case status
        case timeSlot = "time_slot"
        case notes
    }
}

// MARK: - Supplement Categories

enum SupplementCategory: String, CaseIterable {
    case supplement = "supplement"
    case vitamin = "vitamin"
    case mineral = "mineral"
    case medication = "medication"
    case probiotic = "probiotic"
    case herb = "herb"
    case other = "other"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .vitamin: return "pill.fill"
        case .mineral: return "leaf.fill"
        case .medication: return "cross.case.fill"
        case .probiotic: return "allergens"
        case .herb: return "leaf.arrow.triangle.circlepath"
        default: return "pills.fill"
        }
    }
}

// MARK: - Dose Frequency

enum DoseFrequency: String, CaseIterable {
    case daily = "daily"
    case twiceDaily = "twice_daily"
    case threeTimesDaily = "three_times_daily"
    case weekly = "weekly"
    case asNeeded = "as_needed"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .twiceDaily: return "Twice daily"
        case .threeTimesDaily: return "3x daily"
        case .weekly: return "Weekly"
        case .asNeeded: return "As needed"
        }
    }
}

// MARK: - Time of Day

enum TimeOfDay: String, CaseIterable {
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"
    case night = "night"
    case withMeals = "with_meals"

    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        case .withMeals: return "With meals"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.fill"
        case .withMeals: return "fork.knife"
        }
    }
}
