import Foundation

// MARK: - Habit

struct Habit: Codable, Identifiable {
    let id: Int
    let name: String
    let category: String?
    let frequency: String
    let targetCount: Int
    let icon: String?
    let color: String?
    let isActive: Bool
    let completedToday: Bool
    let completionCount: Int
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletions: Int
    let last7Days: [Bool]

    enum CodingKeys: String, CodingKey {
        case id, name, category, frequency, icon, color
        case targetCount = "target_count"
        case isActive = "is_active"
        case completedToday = "completed_today"
        case completionCount = "completion_count"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalCompletions = "total_completions"
        case last7Days = "last_7_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        frequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? "daily"
        targetCount = try container.decodeIfPresent(Int.self, forKey: .targetCount) ?? 1
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        completedToday = try container.decodeIfPresent(Bool.self, forKey: .completedToday) ?? false
        completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        totalCompletions = try container.decodeIfPresent(Int.self, forKey: .totalCompletions) ?? 0
        last7Days = try container.decodeIfPresent([Bool].self, forKey: .last7Days) ?? Array(repeating: false, count: 7)
    }

    init(id: Int, name: String, category: String?, frequency: String, targetCount: Int,
         icon: String?, color: String?, isActive: Bool, completedToday: Bool,
         completionCount: Int, currentStreak: Int, longestStreak: Int,
         totalCompletions: Int, last7Days: [Bool]) {
        self.id = id
        self.name = name
        self.category = category
        self.frequency = frequency
        self.targetCount = targetCount
        self.icon = icon
        self.color = color
        self.isActive = isActive
        self.completedToday = completedToday
        self.completionCount = completionCount
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalCompletions = totalCompletions
        self.last7Days = last7Days
    }

    var toggled: Habit {
        Habit(id: id, name: name, category: category, frequency: frequency,
              targetCount: targetCount, icon: icon, color: color, isActive: isActive,
              completedToday: !completedToday,
              completionCount: completedToday ? 0 : targetCount,
              currentStreak: completedToday ? max(0, currentStreak - 1) : currentStreak + 1,
              longestStreak: longestStreak,
              totalCompletions: completedToday ? max(0, totalCompletions - 1) : totalCompletions + 1,
              last7Days: {
                  var days = last7Days
                  if days.count == 7 { days[6] = !completedToday }
                  return days
              }())
    }
}

// MARK: - HabitCompletion

struct HabitCompletion: Codable, Identifiable {
    let id: Int
    let habitId: Int
    let completedAt: String
    let count: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, count, notes
        case habitId = "habit_id"
        case completedAt = "completed_at"
    }
}

// MARK: - Requests

struct LogHabitRequest: Codable {
    let habitId: Int
    let count: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case count, notes
        case habitId = "habit_id"
    }
}

struct CreateHabitRequest: Codable {
    let name: String
    let category: String?
    let frequency: String?
    let targetCount: Int?
    let icon: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case name, category, frequency, icon, color
        case targetCount = "target_count"
    }
}

// MARK: - Responses

struct HabitsResponse: Codable {
    let success: Bool
    let habits: [Habit]
    let count: Int?
}

struct HabitResponse: Codable {
    let success: Bool
    let habit: Habit
}

struct HabitDeleteResponse: Codable {
    let success: Bool
    let message: String?
    let id: Int?
}
