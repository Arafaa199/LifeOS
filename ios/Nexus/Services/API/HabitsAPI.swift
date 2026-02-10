import Foundation
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "habits-api")

// MARK: - Habits API Client

class HabitsAPI: BaseAPIClient {
    static let shared = HabitsAPI()

    private var cachedWaterHabitId: Int?

    private init() {
        super.init(category: "habits-api")
    }

    func fetchHabits() async throws -> HabitsResponse {
        try await get("/webhook/nexus-habits")
    }

    func completeHabit(_ request: LogHabitRequest) async throws -> HabitResponse {
        try await post("/webhook/nexus-habit-complete", body: request)
    }

    func createHabit(_ request: CreateHabitRequest) async throws -> HabitResponse {
        try await post("/webhook/nexus-habit-create", body: request)
    }

    func deleteHabit(id: Int) async throws -> HabitDeleteResponse {
        let path = buildPath("/webhook/nexus-habit-delete", query: ["id": "\(id)"])
        return try await delete(path)
    }

    // MARK: - Water (via Habits)

    func logWater() async throws -> HabitResponse {
        let habitId = try await resolveWaterHabitId()
        return try await completeHabit(LogHabitRequest(habitId: habitId, count: nil, notes: nil))
    }

    private func resolveWaterHabitId() async throws -> Int {
        if let cached = cachedWaterHabitId { return cached }
        let response = try await fetchHabits()
        guard let water = response.habits.first(where: { $0.name.lowercased() == "water" }) else {
            logger.error("Water habit not found in habits list")
            throw APIError.serverError(404)
        }
        cachedWaterHabitId = water.id
        return water.id
    }
}
